import 'relay_resolver.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:blossom_upload_queue_shim_for_ndk/blossom_upload_queue_shim_for_ndk.dart';
import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:crypto/crypto.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/email.dart';
import '../services/email_parser.dart';
import '../storage/email_repository.dart';
import '../utils/email_record_builder.dart';
import '../utils/encrypt_blob.dart';
import '../utils/mime_message_cleaner.dart';
import '../utils/recipient_resolver.dart';
import 'settings_manager.dart';

/// Handles building, encrypting and sending emails via Nostr GiftWraps.
class EmailSender {
  final Ndk _ndk;
  final EmailParser _parser;
  final SettingsManager _settings;
  final RelayResolver _relays;
  final OfflineBroadcast _broadcastQueue;
  final OfflineBlossomUpload _blossomUploadQueue;
  final BlossomCache _blossomCache;
  final EmailRepository _emailRepo;
  final List<String> _defaultBlossomServers;
  final Map<String, String>? nip05Overrides;

  EmailSender(
    this._ndk,
    this._settings,
    this._relays,
    this._broadcastQueue,
    this._blossomUploadQueue,
    this._blossomCache,
    this._emailRepo, {
    List<String>? defaultBlossomServers,
    this.nip05Overrides,
  }) : _parser = EmailParser(),
       _defaultBlossomServers =
           defaultBlossomServers ?? recommendedBlossomServers;

  String? get _pubkey => _ndk.accounts.getPublicKey();

  void _assertPubkey() {
    if (_pubkey == null) {
      throw NostrMailException('No account configured in ndk');
    }
  }

  /// Send email — auto-detects if recipient is Nostr or legacy email.
  Future<void> send({
    required List<MailAddress> to,
    List<MailAddress>? cc,
    List<MailAddress>? bcc,
    required String subject,
    required String body,
    MailAddress? from,
    String? htmlBody,
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
  }) async {
    _assertPubkey();
    final senderPubkey = _pubkey!;

    final MailAddress finalFrom;
    if (from != null) {
      finalFrom = from;
    } else {
      final cached =
          _settings.cachedPrivateSettings ??
          await _settings.getCachedPrivateSettings();
      if (cached?.identities != null && cached!.identities!.isNotEmpty) {
        finalFrom = cached.identities!.first;
      } else {
        final senderNpub = Nip19.encodePubKey(senderPubkey);
        finalFrom = MailAddress(null, '$senderNpub@nostr');
      }
    }

    final rawContent = _parser.build(
      from: finalFrom,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      htmlBody: htmlBody,
    );

    final message = MimeMessage.parseFromText(rawContent);
    return sendMime(
      message,
      keepCopy: keepCopy,
      signRumor: signRumor,
      isPublic: isPublic,
    );
  }

  /// Send a pre-constructed [MimeMessage].
  Future<void> sendMime(
    MimeMessage message, {
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
  }) async {
    _assertPubkey();
    final senderPubkey = _pubkey!;

    if (isPublic && !signRumor) {
      throw NostrMailException(
        'Public emails must be signed (signRumor must be true)',
      );
    }

    final recipients = <MailAddress>{};
    if (message.to != null) recipients.addAll(message.to!);
    if (message.cc != null) recipients.addAll(message.cc!);
    if (message.bcc != null) recipients.addAll(message.bcc!);

    if (recipients.isEmpty) {
      throw NostrMailException('No recipients found in MimeMessage');
    }

    final fromAddress = message.fromEmail;

    final resolutionFutures = recipients.map((addr) async {
      final pubkey = await resolveRecipient(
        to: addr.encode(),
        from: fromAddress,
        nip05Overrides: nip05Overrides,
      );
      return MapEntry(addr, pubkey);
    });
    final resolutionResults = await Future.wait(resolutionFutures);
    final addressToPubkey = Map<MailAddress, String>.fromEntries(
      resolutionResults,
    );
    final recipientPubkeys = addressToPubkey.values.toSet();

    final publicRecipientPubkeys = <String>{};
    if (message.to != null) {
      publicRecipientPubkeys.addAll(
        message.to!.map((a) => addressToPubkey[a]).whereType<String>(),
      );
    }
    if (message.cc != null) {
      publicRecipientPubkeys.addAll(
        message.cc!.map((a) => addressToPubkey[a]).whereType<String>(),
      );
    }

    final bccRecipientPubkeys = <String>{};
    if (message.bcc != null) {
      bccRecipientPubkeys.addAll(
        message.bcc!.map((a) => addressToPubkey[a]).whereType<String>(),
      );
    }

    final rawContent = message.renderMessage();
    final rawContentBytes = utf8.encode(rawContent);

    final targetPubkeys = <String>{...recipientPubkeys};
    if (keepCopy) targetPubkeys.add(senderPubkey);

    final baseTags = <List<String>>[];
    if (mailFrom != null) baseTags.add(['mail-from', mailFrom]);
    String content = '';

    if (rawContentBytes.length >= maxInlineSize) {
      final encryptedBlob = await encryptBlob(
        Uint8List.fromList(rawContentBytes),
      );

      final allInvolvedPubkeys = <String>{...recipientPubkeys};
      if (keepCopy) allInvolvedPubkeys.add(senderPubkey);

      final allBlossomServers = <String>[];
      final servers = await _ndk.blossomUserServerList.getUserServerList(
        pubkeys: allInvolvedPubkeys.toList(),
      );
      if (servers != null) allBlossomServers.addAll(servers);
      if (allBlossomServers.isEmpty) {
        allBlossomServers.addAll(_defaultBlossomServers);
      }

      final sha256Hash = sha256.convert(encryptedBlob.bytes).toString();
      // The queue reads bytes from the cache when it actually uploads, so
      // the blob has to be there before we enqueue.
      await _blossomCache.put(
        sha256Hash,
        encryptedBlob.bytes,
        type: 'application/octet-stream',
      );
      await _blossomUploadQueue.upload(
        sha256: sha256Hash,
        servers: allBlossomServers.toSet().toList(),
        contentType: 'application/octet-stream',
      );

      baseTags
        ..add(['x', sha256Hash])
        ..add(['encryption-algorithm', 'aes-gcm'])
        ..add(['decryption-key', encryptedBlob.key])
        ..add(['decryption-nonce', encryptedBlob.nonce]);
    }

    if (isPublic) {
      final targetContent = removeBccHeaders(rawContent);
      final targetContentBytes = utf8.encode(targetContent);
      final String finalContent;
      if (targetContentBytes.length < maxInlineSize) {
        finalContent = targetContent;
      } else {
        finalContent = content;
      }

      final tags = List<List<String>>.from(baseTags);
      for (final pubkey in publicRecipientPubkeys) {
        tags.add(['p', pubkey]);
      }

      final emailEvent = Nip01Event(
        pubKey: senderPubkey,
        kind: emailKind,
        tags: tags,
        content: finalContent,
      );

      final signedPublicEvent = await _ndk.accounts.sign(emailEvent);

      final writeRelays = await _relays.getWriteRelays(senderPubkey);

      // Persist the sender's local copy before any broadcast is enqueued.
      // From here on every step is either a local write or a durable
      // enqueue, so a crash between save and broadcast cannot leave the
      // user without a Sent entry.
      Nip01Event? signedSenderRumor;
      if (keepCopy) {
        final senderTags = List<List<String>>.from(baseTags)
          ..add(['p', senderPubkey]);

        final senderEmailEvent = Nip01Event(
          pubKey: senderPubkey,
          kind: emailKind,
          tags: senderTags,
          content: rawContent,
        );

        signedSenderRumor = signRumor
            ? await _ndk.accounts.sign(senderEmailEvent)
            : senderEmailEvent;

        await _saveSelfCopy(
          rumor: signedSenderRumor,
          mimeContent: rawContent,
          senderPubkey: senderPubkey,
          isPublic: true,
        );
      }

      await _broadcastQueue.broadcast(signedPublicEvent, relays: writeRelays);

      final bccTags = List<List<String>>.from(baseTags)
        ..add(['public-ref', signedPublicEvent.id, ...writeRelays]);

      final bccRumor = Nip01Event(
        pubKey: senderPubkey,
        kind: emailKind,
        tags: bccTags,
        content: finalContent,
      );

      final signedBccRumor = await _ndk.accounts.sign(bccRumor);

      final bccFutures = bccRecipientPubkeys.map((pubkey) async {
        await _publishGiftWrapped(signedBccRumor, pubkey);
      });

      if (signedSenderRumor != null) {
        await _publishGiftWrapped(signedSenderRumor, senderPubkey);
      }

      await Future.wait(bccFutures);
    } else {
      // Build and persist the sender's local copy before any broadcast.
      // Every network-required step (recipient resolution, Blossom server
      // lookup) has already succeeded by this point — anything past here
      // is a local write or a durable enqueue. Saving up-front guarantees
      // the email lands in the local Sent folder even if a per-recipient
      // sign call fails inside the parallel publish below.
      Nip01Event? senderRumor;
      if (keepCopy) {
        final senderContentBytes = utf8.encode(rawContent);
        final senderContent = senderContentBytes.length < maxInlineSize
            ? rawContent
            : content;
        final senderTags = List<List<String>>.from(baseTags)
          ..insert(0, ['p', senderPubkey]);
        final senderEvent = Nip01Event(
          pubKey: senderPubkey,
          kind: emailKind,
          tags: senderTags,
          content: senderContent,
        );
        senderRumor = signRumor
            ? await _ndk.accounts.sign(senderEvent)
            : senderEvent;
        await _saveSelfCopy(
          rumor: senderRumor,
          mimeContent: rawContent,
          senderPubkey: senderPubkey,
          isPublic: false,
        );
      }

      final sendFutures = targetPubkeys.map((pubkey) async {
        // Reuse the pre-built sender rumor so rumor.id stays stable:
        // when the gift wrap comes back via sync, the dedup is a no-op.
        if (keepCopy && pubkey == senderPubkey) {
          await _publishGiftWrapped(senderRumor!, pubkey);
          return;
        }

        final targetContent = removeBccHeaders(rawContent);
        final targetContentBytes = utf8.encode(targetContent);
        final finalContent = targetContentBytes.length < maxInlineSize
            ? targetContent
            : content;

        final tags = List<List<String>>.from(baseTags)
          ..insert(0, ['p', pubkey]);

        final emailEvent = Nip01Event(
          pubKey: senderPubkey,
          kind: emailKind,
          tags: tags,
          content: finalContent,
        );

        final eventToPublish = signRumor
            ? await _ndk.accounts.sign(emailEvent)
            : emailEvent;

        await _publishGiftWrapped(eventToPublish, pubkey);
      });

      await Future.wait(sendFutures);
    }
  }

  /// Optimistic local write of the sender's own copy.
  ///
  /// The same rumor will eventually come back via the gift wrap sync. Saving
  /// it now means the UI shows the email in `Sent` instantly, independently
  /// of relay round-trips. The save is idempotent on `rumor.id`, so the
  /// sync-engine path is a no-op once the gift wrap arrives.
  Future<void> _saveSelfCopy({
    required Nip01Event rumor,
    required String mimeContent,
    required String senderPubkey,
    required bool isPublic,
  }) async {
    final mimeMessage = MimeMessage.parseFromText(mimeContent);
    final email = Email(
      id: rumor.id,
      senderPubkey: senderPubkey,
      recipientPubkey: senderPubkey,
      rawContent: mimeContent,
      createdAt: DateTime.fromMillisecondsSinceEpoch(rumor.createdAt * 1000),
      isPublic: isPublic,
      mimeMessage: mimeMessage,
    );
    final record = buildEmailRecord(email: email, folder: 'sent');
    await _emailRepo.save(record);
  }

  Future<void> _publishGiftWrapped(
    Nip01Event event,
    String recipientPubkey,
  ) async {
    final giftWrapEvent = await _ndk.giftWrap.toGiftWrap(
      rumor: event,
      recipientPubkey: recipientPubkey,
    );
    // Gift wraps go to the recipient's DM relays (NIP-17).
    final dmRelays = await _relays.getDmRelays(recipientPubkey);
    await _broadcastQueue.broadcast(giftWrapEvent, relays: dmRelays);
  }
}
