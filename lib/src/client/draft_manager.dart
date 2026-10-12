import 'dart:convert';
import 'dart:math';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/draft.dart';
import '../storage/draft_repository.dart';
import '../utils/rumor_mime_text.dart';
import 'email_sender.dart';
import 'relay_resolver.dart';

/// Saves and reads email drafts: NIP-37 draft wraps (kind 31234, `k` 1301)
/// holding the self-copy rumor sending the email would build.
///
/// Local-first: a save or a delete lands in the local store at once, and its
/// wrap goes to the private relays through the broadcast queue. Versions from
/// other devices come in through [MailSync].
class DraftManager {
  final Ndk _ndk;
  final DraftRepository _repo;
  final EmailSender _sender;
  final RelayResolver _relays;
  final OfflineBroadcast _broadcastQueue;
  final BlossomCache _blossomCache;
  final List<String>? _defaultBlossomServers;

  DraftManager(
    this._ndk,
    this._repo,
    this._sender,
    this._relays,
    this._broadcastQueue,
    this._blossomCache, {
    this._defaultBlossomServers,
  });

  static final _random = Random.secure();

  /// Save [message] as a new version of [draftId], or as a new draft when
  /// [draftId] is null. [mailFrom] is the `mail-from` sending would carry.
  Future<Draft> save(
    MimeMessage message, {
    String? draftId,
    String? mailFrom,
  }) async {
    final account = _signingAccount();
    final pubkey = account.pubkey;
    draftId ??= _newDraftId();

    final createdAt = await _nextCreatedAt(draftId, pubkey);
    final rumor = await _sender.buildSelfRumor(
      message,
      mailFrom: mailFrom,
      createdAt: createdAt,
    );
    final plaintext = jsonEncode(
      Nip01EventModel.fromEntity(rumor).toJson()..remove('sig'),
    );
    final content = await account.signer.encryptNip44(
      plaintext: plaintext,
      recipientPubKey: pubkey,
    );
    if (content == null) {
      throw NostrMailException('Failed to encrypt the draft');
    }

    final wrap = await _signWrap(account, draftId, createdAt, content);
    await _repo.saveDecryption(
      eventId: wrap.id,
      recipientPubkey: pubkey,
      plaintext: plaintext,
    );
    await _repo.saveVersion(
      draftId: draftId,
      recipientPubkey: pubkey,
      eventId: wrap.id,
      createdAt: createdAt,
      message: message,
    );
    await _broadcast(wrap);

    return (await _repo.find(draftId, recipientPubkey: pubkey))!;
  }

  /// Delete [draftId]: a blank wrap replaces it, as NIP-37 says.
  Future<void> delete(String draftId) async {
    final account = _signingAccount();
    final pubkey = account.pubkey;

    final createdAt = await _nextCreatedAt(draftId, pubkey);
    final wrap = await _signWrap(account, draftId, createdAt, '');
    await _repo.saveVersion(
      draftId: draftId,
      recipientPubkey: pubkey,
      eventId: wrap.id,
      createdAt: createdAt,
    );
    await _broadcast(wrap);
  }

  /// The drafts of the logged account, most recently saved first.
  Future<List<Draft>> list() => _repo.list(recipientPubkey: _requirePubkey());

  /// Reactive [list].
  Stream<List<Draft>> watch() => _repo.watch(recipientPubkey: _requirePubkey());

  /// The full MIME text of [draftId], or null when it is unknown or deleted.
  /// Throws when its Blossom blob is neither cached nor downloadable.
  Future<String?> getMimeText(String draftId) async {
    final pubkey = _requirePubkey();
    final row = await _repo.get(draftId, recipientPubkey: pubkey);
    if (row == null || row.deleted) return null;
    final decryption = await _repo.getDecryption(
      row.eventId,
      recipientPubkey: pubkey,
    );
    final plaintext = decryption?.plaintext;
    if (plaintext == null) return null;

    final rumor = Nip01EventModel.fromJson(
      jsonDecode(plaintext) as Map<String, dynamic>,
    );
    return rumorMimeText(
      rumor,
      ndk: _ndk,
      cache: _blossomCache,
      pinFor: pubkey,
      defaultBlossomServers: _defaultBlossomServers,
    );
  }

  String _requirePubkey() {
    final pubkey = _ndk.accounts.getPublicKey();
    if (pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }
    return pubkey;
  }

  Account _signingAccount() {
    final account = _ndk.accounts.getLoggedAccount();
    if (account == null) {
      throw NostrMailException('No account configured in ndk');
    }
    if (!account.signer.canSign()) {
      throw NostrMailException('Cannot save drafts: no signing capability');
    }
    return account;
  }

  /// 32 random lowercase hex characters.
  static String _newDraftId() => [
    for (var i = 0; i < 16; i++)
      _random.nextInt(256).toRadixString(16).padLeft(2, '0'),
  ].join();

  /// Now, or later than the current version: two saves in the same second
  /// would tie, and NIP-01 would keep the lowest id.
  Future<int> _nextCreatedAt(String draftId, String pubkey) async {
    final current = await _repo.get(draftId, recipientPubkey: pubkey);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final previous = current?.createdAt ?? 0;
    return now > previous ? now : previous + 1;
  }

  Future<Nip01Event> _signWrap(
    Account account,
    String draftId,
    int createdAt,
    String content,
  ) async {
    final wrap = await account.signer.sign(
      Nip01Event(
        pubKey: account.pubkey,
        kind: draftWrapKind,
        createdAt: createdAt,
        tags: [
          ['d', draftId],
          ['k', emailKind.toString()],
        ],
        content: content,
      ),
    );
    await _ndk.config.cache.saveEvent(wrap);
    return wrap;
  }

  Future<void> _broadcast(Nip01Event wrap) => _broadcastQueue.broadcast(
    wrap,
    relaySet: _relays.draftRelaySet(wrap.pubKey),
    pubkey: wrap.pubKey,
  );
}
