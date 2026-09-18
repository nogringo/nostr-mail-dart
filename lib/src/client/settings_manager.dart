import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart' hide RelaySet;
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;
import 'package:rxdart/rxdart.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/ndk_data_response.dart';
import '../models/private_settings.dart';
import '../storage/settings_repository.dart';
import 'relay_resolver.dart';

/// Manages NIP-78 private settings (cross-device encrypted sync).
class SettingsManager {
  final Ndk _ndk;
  final SettingsRepository _repo;
  final RelayResolver _relays;
  final OfflineBroadcast _broadcastQueue;
  final Map<String, PrivateSettings?> _cache = {};

  SettingsManager(this._ndk, this._repo, this._relays, this._broadcastQueue);

  String? get _pubkey => _ndk.accounts.getPublicKey();

  /// Synchronous in-memory cache read. [pubkey] defaults to the logged account.
  PrivateSettings? cachedPrivateSettings({String? pubkey}) {
    pubkey ??= _pubkey;
    if (pubkey == null) return null;
    return _cache[pubkey];
  }

  /// Async read from local decrypted cache (no signer needed). [pubkey]
  /// defaults to the logged account.
  Future<PrivateSettings?> getLocalPrivateSettings({String? pubkey}) async {
    pubkey ??= _pubkey;
    if (pubkey == null) return null;

    final cached = _cache[pubkey];
    if (cached != null) return cached;

    final json = await _repo.load(pubkey: pubkey);
    if (json == null || json.isEmpty) return null;

    final settings = PrivateSettings.fromJson(json);
    _cache[pubkey] = settings;
    return settings;
  }

  /// Fetch from relays, decrypt, and cache locally. [pubkey] defaults to the
  /// logged account.
  Future<PrivateSettings?> fetchPrivateSettings({String? pubkey}) async {
    final account = _signingAccount(pubkey);
    pubkey = account.pubkey;
    final writeRelays = await _relays.getWriteRelays(pubkey);

    final response = _ndk.requests.query(
      filter: _filter(pubkey),
      explicitRelays: writeRelays,
      auth: RelayAuth.allow(account),
    );

    final events = await response.future;
    if (events.isEmpty) return null;

    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);

    try {
      return await _decryptAndCache(event, account);
    } catch (_) {
      return null;
    }
  }

  /// Local-first read (ndk ADR #702): emits the local settings, then every
  /// newer relay copy. A relay copy that is undecryptable, or no relay
  /// answering, is reported as a stream error rather than `null`.
  ///
  /// [pubkey] defaults to the logged account. Any other account must be known
  /// to ndk with a signer, since only its owner can decrypt its settings.
  NdkDataResponse<PrivateSettings> getPrivateSettings({
    String? pubkey,
    Duration? timeout,
  }) {
    final account = _signingAccount(pubkey);

    final subject = BehaviorSubject<NdkValue<PrivateSettings>>();
    _load(subject, account, timeout)
        .catchError((Object e, StackTrace st) => subject.addError(e, st))
        .whenComplete(subject.close);
    return NdkDataResponse(subject);
  }

  Future<void> _load(
    BehaviorSubject<NdkValue<PrivateSettings>> subject,
    Account account,
    Duration? timeout,
  ) async {
    final pubkey = account.pubkey;

    PrivateSettings? local;
    try {
      local = await getLocalPrivateSettings(pubkey: pubkey);
    } catch (_) {}
    subject.add(NdkValue(local, DataOrigin.cache));

    final writeRelays = await _relays.getWriteRelays(pubkey);
    final response = _ndk.requests.query(
      filter: _filter(pubkey),
      explicitRelays: writeRelays,
      auth: RelayAuth.allow(account),
      cacheRead: false,
      timeout: timeout,
    );

    // A local write still in the broadcast queue beats older relay copies.
    final localEvent = local?.sourceEvent;
    Nip01Event? best;
    var bestReadable = false;
    var received = false;

    await for (final event in response.stream) {
      received = true;
      if (localEvent != null && _supersedes(localEvent, event)) continue;
      if (best != null && !_supersedes(event, best)) continue;
      best = event;
      try {
        subject.add(
          NdkValue(await _decryptAndCache(event, account), DataOrigin.relays),
        );
        bestReadable = true;
      } catch (_) {
        bestReadable = false;
      }
    }

    if (best != null) {
      if (!bestReadable) {
        throw NostrMailException('Cannot decrypt private settings');
      }
      return;
    }
    if (received || localEvent != null) return;

    final outcomes = await response.relayOutcomesDone;
    if (!outcomes.values.any((o) => o.status == RelayRequestStatus.eose)) {
      throw NostrMailException('No relay answered for private settings');
    }
    subject.add(const NdkValue(null, DataOrigin.relays));
  }

  Account _signingAccount(String? pubkey) {
    final account = pubkey == null
        ? _ndk.accounts.getLoggedAccount()
        : _ndk.accounts.accounts[pubkey];
    if (account == null) {
      throw NostrMailException('No account configured in ndk');
    }
    if (!account.signer.canSign()) {
      throw NostrMailException(
        'Cannot access private settings: no signing capability',
      );
    }
    return account;
  }

  /// NIP-01 replaceable ordering: highest `created_at`, then lowest id.
  static bool _supersedes(Nip01Event a, Nip01Event b) =>
      a.createdAt > b.createdAt ||
      (a.createdAt == b.createdAt && a.id.compareTo(b.id) < 0);

  ndk.Filter _filter(String pubkey) =>
      ndk.Filter(kinds: [appSettingsKind], authors: [pubkey], limit: 1)
        ..setTag('d', [privateSettingsDTag]);

  Future<PrivateSettings> _decryptAndCache(
    Nip01Event event,
    Account account,
  ) async {
    final pubkey = event.pubKey;
    final decrypted = await account.signer.decryptNip44(
      ciphertext: event.content,
      senderPubKey: pubkey,
    );
    if (decrypted == null || decrypted.isEmpty) {
      throw NostrMailException('Cannot decrypt private settings');
    }

    final settings = PrivateSettings.fromJson(decrypted, sourceEvent: event);
    await _repo.save(pubkey: pubkey, json: decrypted);
    _cache[pubkey] = settings;
    return settings;
  }

  /// Encrypt and publish private settings to relays. [pubkey] defaults to the
  /// logged account.
  Future<void> setPrivateSettings(
    PrivateSettings settings, {
    String? pubkey,
  }) async {
    final account = _signingAccount(pubkey);
    pubkey = account.pubkey;

    final encrypted = await account.signer.encryptNip44(
      plaintext: settings.toJson(),
      recipientPubKey: pubkey,
    );
    if (encrypted == null) {
      throw NostrMailException('Failed to encrypt private settings');
    }

    // Two writes in the same second would tie, and NIP-01 would keep the lowest id.
    final previous = _cache[pubkey]?.sourceEvent?.createdAt ?? 0;
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    final event = Nip01Event(
      pubKey: pubkey,
      kind: appSettingsKind,
      createdAt: now > previous ? now : previous + 1,
      tags: [
        ['d', privateSettingsDTag],
      ],
      content: encrypted,
    );

    final signed = await account.signer.sign(event);

    await _repo.save(pubkey: pubkey, json: settings.toJson());
    _cache[pubkey] = PrivateSettings(
      sourceEvent: signed,
      signature: settings.signature,
      bridges: settings.bridges,
      identities: settings.identities,
    );

    await _broadcastQueue.broadcast(
      signed,
      relaySet: _relays.writeRelaySet(pubkey),
      pubkey: pubkey,
    );
  }

  /// Update a single field in private settings and enqueue relay sync.
  Future<void> updatePrivateSettings({
    String? signature,
    List<String>? bridges,
    List<MailAddress>? identities,
    bool clearSignature = false,
    bool clearBridges = false,
    bool clearIdentities = false,
    String? pubkey,
  }) async {
    final current =
        await getLocalPrivateSettings(pubkey: pubkey) ??
        const PrivateSettings();
    final updated = current.copyWith(
      signature: signature,
      bridges: bridges,
      identities: identities,
      clearSignature: clearSignature,
      clearBridges: clearBridges,
      clearIdentities: clearIdentities,
    );
    await setPrivateSettings(updated, pubkey: pubkey);
  }

  void clearCache({String? pubkey}) {
    if (pubkey == null) {
      _cache.clear();
      return;
    }
    _cache.remove(pubkey);
  }
}
