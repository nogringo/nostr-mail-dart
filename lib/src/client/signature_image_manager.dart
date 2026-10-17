import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:blossom_upload_queue_shim_for_ndk/blossom_upload_queue_shim_for_ndk.dart';
import 'package:cryptography/cryptography.dart' show Sha256;
import 'package:ndk/ndk.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/inline_signature.dart';
import '../models/private_settings.dart';
import '../models/signature.dart';
import '../utils/blob_fetcher.dart';
import '../utils/decrypt_blob.dart';
import '../utils/encrypt_blob.dart';
import 'settings_manager.dart';

/// Images of the signatures, as encrypted blobs on the account's Blossom
/// servers
/// ([Nostr Mail Settings](https://github.com/nogringo/protocols/blob/main/nostr-mail-settings.md#signature-images)).
class SignatureImageManager {
  final Ndk _ndk;
  final SettingsManager _settings;
  final OfflineBlossomUpload _uploads;
  final BlossomCache _cache;
  final List<String> _defaultBlossomServers;

  SignatureImageManager(
    this._ndk,
    this._settings,
    this._uploads,
    this._cache, {
    List<String>? defaultBlossomServers,
  }) : _defaultBlossomServers =
           defaultBlossomServers ?? recommendedBlossomServers;

  static const _contentType = 'application/octet-stream';

  String get _pubkey {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) throw NostrMailException('No account logged in');
    return pubkey;
  }

  Future<PrivateSettings> _current() async =>
      await _settings.getLocalPrivateSettings() ?? const PrivateSettings();

  Future<String> add(
    Uint8List bytes, {
    required String mimeType,
    String? dim,
  }) async {
    final pubkey = _pubkey;
    final encrypted = await encryptBlob(bytes);
    // Pinned: a signature image is read again on every send.
    final descriptor = await _cache.put(
      encrypted.bytes,
      type: _contentType,
      pinBy: blobPinHolder(pubkey),
    );
    await _uploads.upload(
      sha256: descriptor.sha256,
      serverSet: UrlSet.fallback([
        UrlSet.blossom(pubkey),
        UrlSet.explicit(_defaultBlossomServers),
      ]),
      contentType: _contentType,
      pubkey: pubkey,
    );
    final current = await _current();
    await _settings.setPrivateSettings(
      current.copyWith(
        signatureImages: {
          ...?current.signatureImages,
          descriptor.sha256: SignatureImage(
            decryptionKey: encrypted.key,
            decryptionNonce: encrypted.nonce,
            mimeType: mimeType,
            size: encrypted.bytes.length,
            dim: dim,
          ),
        },
      ),
    );
    return descriptor.sha256;
  }

  Future<Uint8List?> get(String key, {String? pubkey}) async {
    pubkey ??= _pubkey;
    final settings = await _settings.getLocalPrivateSettings(pubkey: pubkey);
    final image = settings?.signatureImages?[key];
    if (image == null) return null;
    if (image.encryptionAlgorithm != 'aes-gcm') {
      throw NostrMailException(
        'Unsupported encryption algorithm: ${image.encryptionAlgorithm}',
      );
    }
    final encrypted = await fetchOrLoadEncryptedBlob(
      blossomHash: key,
      involvedPubkeys: [pubkey],
      cache: _cache,
      ndk: _ndk,
      pinFor: pubkey,
      defaultBlossomServers: _defaultBlossomServers,
    );
    final hash = await Sha256().hash(encrypted);
    if (hash.bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join() !=
        key) {
      await _cache.delete(key);
      throw NostrMailException('Signature image $key does not match its hash');
    }
    return decryptBlob(
      encryptedBytes: encrypted,
      key: image.decryptionKey,
      nonce: image.decryptionNonce,
    );
  }

  /// Deleting the blob from the Blossom servers is best effort and not
  /// awaited: the servers may be unreachable, and the key is gone anyway.
  Future<void> remove(String key) async {
    final pubkey = _pubkey;
    final current = await _current();
    final images = current.signatureImages;
    if (images == null || !images.containsKey(key)) return;
    await _settings.setPrivateSettings(
      current.copyWith(signatureImages: {...images}..remove(key)),
    );
    await _uploads.remove(key, pubkey: pubkey);
    await _cache.unpin(key, by: blobPinHolder(pubkey));
    _deleteBlob(key, pubkey).ignore();
  }

  Future<void> _deleteBlob(String key, String pubkey) async {
    final servers = {
      ...?await _ndk.blossomUserServerList.getUserServerList(pubkeys: [pubkey]),
      ..._defaultBlossomServers,
    };
    await _ndk.blossom.deleteBlob(sha256: key, serverUrls: servers.toList());
  }

  static final _imgSrc = RegExp(
    r'''(<img\b[^>]*?\bsrc\s*=\s*)(["'])([^"']*)\2''',
    caseSensitive: false,
  );

  Future<InlineSignature> inline(Signature signature) async {
    final known = (await _current()).signatureImages ?? const {};
    final keys = {
      for (final m in _imgSrc.allMatches(signature.html))
        if (known.containsKey(m[3])) m[3]!,
    };
    final images = {
      for (final key in keys)
        key: InlineImage(
          contentId: '$key@nostr-mail',
          mimeType: known[key]!.mimeType,
          bytes: (await get(key))!,
        ),
    };
    final html = signature.html.replaceAllMapped(_imgSrc, (m) {
      final image = images[m[3]];
      if (image == null) return m[0]!;
      return '${m[1]}${m[2]}cid:${image.contentId}${m[2]}';
    });
    return InlineSignature(html: html, images: images.values.toList());
  }
}
