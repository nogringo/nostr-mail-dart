import 'dart:math';

import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart' hide RelaySet;
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;
import 'package:rxdart/rxdart.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/mail_entry.dart';
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
      auth: AuthPolicy.allow(account),
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
      auth: AuthPolicy.allow(account),
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
    _cache[pubkey] = settings.withSource(signed);

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
    List<MailEntry>? folders,
    List<MailEntry>? tags,
    bool clearSignature = false,
    bool clearBridges = false,
    bool clearIdentities = false,
    bool clearFolders = false,
    bool clearTags = false,
    String? pubkey,
  }) async {
    final current =
        await getLocalPrivateSettings(pubkey: pubkey) ??
        const PrivateSettings();
    final updated = current.copyWith(
      signature: signature,
      bridges: bridges,
      identities: identities,
      folders: folders,
      tags: tags,
      clearSignature: clearSignature,
      clearBridges: clearBridges,
      clearIdentities: clearIdentities,
      clearFolders: clearFolders,
      clearTags: clearTags,
    );
    await setPrivateSettings(updated, pubkey: pubkey);
  }

  // ── User folders and tags ───────────────────────────────────────────────

  Future<MailEntry> createFolder(
    String name, {
    String? color,
    MailMatch? match,
  }) => _create(folders: true, name: name, color: color, match: match);

  Future<MailEntry> createTag(String name, {String? color, MailMatch? match}) =>
      _create(folders: false, name: name, color: color, match: match);

  Future<MailEntry> updateFolder(
    String id, {
    String? name,
    String? color,
    int? position,
    MailMatch? match,
    bool clearColor = false,
    bool clearPosition = false,
    bool clearMatch = false,
  }) => _update(
    folders: true,
    id: id,
    edit: (entry) => entry.copyWith(
      name: name,
      color: color,
      position: position,
      match: match,
      clearColor: clearColor,
      clearPosition: clearPosition,
      clearMatch: clearMatch,
    ),
  );

  Future<MailEntry> updateTag(
    String id, {
    String? name,
    String? color,
    int? position,
    MailMatch? match,
    bool clearColor = false,
    bool clearPosition = false,
    bool clearMatch = false,
  }) => _update(
    folders: false,
    id: id,
    edit: (entry) => entry.copyWith(
      name: name,
      color: color,
      position: position,
      match: match,
      clearColor: clearColor,
      clearPosition: clearPosition,
      clearMatch: clearMatch,
    ),
  );

  /// Emails labelled with the folder keep the label, under its id.
  Future<void> deleteFolder(String id) => _delete(folders: true, id: id);

  /// Emails labelled with the tag keep the label, under its id.
  Future<void> deleteTag(String id) => _delete(folders: false, id: id);

  static final _random = Random.secure();
  static final _colorPattern = RegExp(r'^#[0-9a-fA-F]{6}$');

  Future<MailEntry> _create({
    required bool folders,
    required String name,
    String? color,
    MailMatch? match,
  }) async {
    final current = await _current();
    final entries = _entriesOf(current, folders: folders);
    final taken = {
      for (final e in [...?current.folders, ...?current.tags]) e.id,
    };
    String id;
    do {
      id = [
        for (var i = 0; i < 8; i++)
          _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
      ].join();
    } while (taken.contains(id));

    final positions = entries.map((e) => e.position).nonNulls;
    final entry = _validated(
      MailEntry(
        id: id,
        name: name,
        color: color,
        position: positions.isEmpty ? 0 : positions.reduce(max) + 1,
        match: match,
      ),
      entries,
    );
    await _save(current, folders: folders, entries: [...entries, entry]);
    return entry;
  }

  Future<MailEntry> _update({
    required bool folders,
    required String id,
    required MailEntry Function(MailEntry) edit,
  }) async {
    final current = await _current();
    final entries = _entriesOf(current, folders: folders);
    final index = entries.indexWhere((e) => e.id == id);
    if (index < 0) throw NostrMailException('No such folder or tag: $id');
    final entry = _validated(edit(entries[index]), entries);
    await _save(
      current,
      folders: folders,
      entries: [...entries]..[index] = entry,
    );
    return entry;
  }

  Future<void> _delete({required bool folders, required String id}) async {
    final current = await _current();
    final entries = _entriesOf(current, folders: folders);
    if (!entries.any((e) => e.id == id)) return;
    await _save(
      current,
      folders: folders,
      entries: entries.where((e) => e.id != id).toList(),
    );
  }

  Future<PrivateSettings> _current() async =>
      await getLocalPrivateSettings() ?? const PrivateSettings();

  static List<MailEntry> _entriesOf(
    PrivateSettings settings, {
    required bool folders,
  }) => (folders ? settings.folders : settings.tags) ?? const [];

  Future<void> _save(
    PrivateSettings current, {
    required bool folders,
    required List<MailEntry> entries,
  }) => setPrivateSettings(
    folders
        ? current.copyWith(folders: entries)
        : current.copyWith(tags: entries),
  );

  /// [entry] with its name trimmed, once checked against the other [entries]
  /// of its array.
  static MailEntry _validated(MailEntry entry, List<MailEntry> entries) {
    final name = entry.name.trim();
    if (name.isEmpty || name.length > 64) {
      throw NostrMailException('A name takes 1 to 64 characters');
    }
    final lower = name.toLowerCase();
    if (entries.any(
      (e) => e.id != entry.id && e.name.trim().toLowerCase() == lower,
    )) {
      throw NostrMailException('"$name" already exists');
    }
    final color = entry.color;
    if (color != null && !_colorPattern.hasMatch(color)) {
      throw NostrMailException('A color is #RRGGBB, got "$color"');
    }
    return entry.copyWith(name: name);
  }

  void clearCache({String? pubkey}) {
    if (pubkey == null) {
      _cache.clear();
      return;
    }
    _cache.remove(pubkey);
  }
}
