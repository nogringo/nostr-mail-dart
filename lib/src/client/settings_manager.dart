import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;

import '../constants.dart';
import '../exceptions.dart';
import '../models/private_settings.dart';
import '../storage/settings_repository.dart';
import 'relay_resolver.dart';

/// Manages NIP-78 private settings (cross-device encrypted sync).
class SettingsManager {
  final Ndk _ndk;
  final SettingsRepository _repo;
  final RelayResolver _relays;
  final Map<String, PrivateSettings?> _cache = {};

  SettingsManager(this._ndk, this._repo, this._relays);

  String? get _pubkey => _ndk.accounts.getPublicKey();

  void _assertPubkey() {
    if (_pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }
  }

  void _assertSigner() {
    final account = _ndk.accounts.getLoggedAccount();
    if (account == null || !account.signer.canSign()) {
      throw NostrMailException(
        'Cannot access private settings: no signing capability',
      );
    }
  }

  /// Synchronous in-memory cache read.
  PrivateSettings? get cachedPrivateSettings {
    final pubkey = _pubkey;
    if (pubkey == null) return null;
    return _cache[pubkey];
  }

  /// Async read from local decrypted cache (no signer needed).
  Future<PrivateSettings?> getCachedPrivateSettings() async {
    final pubkey = _pubkey;
    if (pubkey == null) return null;

    final cached = _cache[pubkey];
    if (cached != null) return cached;

    final json = await _repo.load(pubkey: pubkey);
    if (json == null || json.isEmpty) return null;

    final settings = PrivateSettings.fromJson(json);
    _cache[pubkey] = settings;
    return settings;
  }

  /// Fetch from relays, decrypt, and cache locally.
  Future<PrivateSettings?> getPrivateSettings() async {
    _assertPubkey();
    _assertSigner();

    final pubkey = _pubkey!;
    final account = _ndk.accounts.getLoggedAccount()!;
    final writeRelays = await _relays.getWriteRelays(pubkey);

    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [appSettingsKind], authors: [pubkey], limit: 1)
        ..setTag('d', [privateSettingsDTag]),
      explicitRelays: writeRelays,
    );

    final events = await response.future;
    if (events.isEmpty) return null;

    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);

    try {
      final decrypted = await account.signer.decryptNip44(
        ciphertext: event.content,
        senderPubKey: pubkey,
      );
      if (decrypted == null || decrypted.isEmpty) return null;

      await _repo.save(pubkey: pubkey, json: decrypted);

      final settings = PrivateSettings.fromJson(decrypted, sourceEvent: event);
      _cache[pubkey] = settings;
      return settings;
    } catch (_) {
      return null;
    }
  }

  /// Encrypt and publish private settings to relays.
  Future<void> setPrivateSettings(PrivateSettings settings) async {
    _assertPubkey();
    _assertSigner();

    final pubkey = _pubkey!;
    final account = _ndk.accounts.getLoggedAccount()!;

    final encrypted = await account.signer.encryptNip44(
      plaintext: settings.toJson(),
      recipientPubKey: pubkey,
    );
    if (encrypted == null) {
      throw NostrMailException('Failed to encrypt private settings');
    }

    final event = Nip01Event(
      pubKey: pubkey,
      kind: appSettingsKind,
      tags: [
        ['d', privateSettingsDTag],
      ],
      content: encrypted,
    );

    final signed = await _ndk.accounts.sign(event);

    await _repo.save(pubkey: pubkey, json: settings.toJson());
    _cache[pubkey] = PrivateSettings(
      sourceEvent: signed,
      signature: settings.signature,
      bridges: settings.bridges,
      identities: settings.identities,
    );

    final writeRelays = await _relays.getWriteRelays(pubkey);
    final broadcast = _ndk.broadcast.broadcast(
      nostrEvent: signed,
      specificRelays: writeRelays,
    );
    await broadcast.broadcastDoneFuture;
  }

  /// Update a single field in private settings.
  Future<void> updatePrivateSettings({
    String? signature,
    List<String>? bridges,
    List<MailAddress>? identities,
    bool clearSignature = false,
    bool clearBridges = false,
    bool clearIdentities = false,
  }) async {
    final current = await getPrivateSettings() ?? const PrivateSettings();
    final updated = current.copyWith(
      signature: signature,
      bridges: bridges,
      identities: identities,
      clearSignature: clearSignature,
      clearBridges: clearBridges,
      clearIdentities: clearIdentities,
    );
    await setPrivateSettings(updated);
  }

  void clearCache() {
    _cache.clear();
    _repo.clear();
  }
}
