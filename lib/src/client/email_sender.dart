import 'dart:convert';
import 'dart:typed_data';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/domain_layer/entities/filter.dart' as ndk;

import '../constants.dart';
import '../exceptions.dart';
import '../services/email_parser.dart';
import '../utils/encrypt_blob.dart';
import '../utils/mime_message_cleaner.dart';
import '../utils/recipient_resolver.dart';
import 'settings_manager.dart';

/// Handles building, encrypting and sending emails via Nostr GiftWraps.
class EmailSender {
  final Ndk _ndk;
  final EmailParser _parser;
  final SettingsManager _settings;
  final List<String> _defaultDmRelays;
  final List<String> _defaultBlossomServers;
  final Map<String, String>? nip05Overrides;

  EmailSender(
    this._ndk,
    this._settings, {
    List<String>? defaultDmRelays,
    List<String>? defaultBlossomServers,
    this.nip05Overrides,
  }) : _parser = EmailParser(),
       _defaultDmRelays = defaultDmRelays ?? recommendedDmRelays,
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

      final uploadResults = await _ndk.blossom.uploadBlob(
        data: encryptedBlob.bytes,
        serverUrls: allBlossomServers.toSet().toList(),
      );

      final successfulUpload = uploadResults.firstWhere(
        (result) => result.success && result.descriptor != null,
        orElse: () => throw NostrMailException('Failed to upload to Blossom'),
      );
      final sha256Hash = successfulUpload.descriptor!.sha256;

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

      final writeRelays = await _getWriteRelays(senderPubkey);
      final broadcast = _ndk.broadcast.broadcast(
        nostrEvent: signedPublicEvent,
        specificRelays: writeRelays,
      );
      await broadcast.broadcastDoneFuture;

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

      if (keepCopy) {
        final senderTags = List<List<String>>.from(baseTags)
          ..add(['p', senderPubkey]);

        final senderEmailEvent = Nip01Event(
          pubKey: senderPubkey,
          kind: emailKind,
          tags: senderTags,
          content: rawContent,
        );

        final signedSenderRumor = signRumor
            ? await _ndk.accounts.sign(senderEmailEvent)
            : senderEmailEvent;

        await _publishGiftWrapped(signedSenderRumor, senderPubkey);
      }

      await Future.wait(bccFutures);
    } else {
      final sendFutures = targetPubkeys.map((pubkey) async {
        String targetContent;
        if (keepCopy && pubkey == senderPubkey) {
          targetContent = rawContent;
        } else {
          targetContent = removeBccHeaders(rawContent);
        }

        final String finalContent;
        final targetContentBytes = utf8.encode(targetContent);
        if (targetContentBytes.length < maxInlineSize) {
          finalContent = targetContent;
        } else {
          finalContent = content;
        }

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

  Future<void> _publishGiftWrapped(
    Nip01Event event,
    String recipientPubkey,
  ) async {
    final giftWrapEvent = await _ndk.giftWrap.toGiftWrap(
      rumor: event,
      recipientPubkey: recipientPubkey,
    );
    final broadcast = _ndk.broadcast.broadcast(nostrEvent: giftWrapEvent);
    await broadcast.broadcastDoneFuture;
  }

  Future<List<String>> _getWriteRelays(String pubkey) async {
    final response = _ndk.requests.query(
      filter: ndk.Filter(kinds: [relayListKind], authors: [pubkey], limit: 1),
    );
    final events = await response.future;
    if (events.isEmpty) return _defaultDmRelays;

    final event = events.reduce((a, b) => a.createdAt > b.createdAt ? a : b);
    final relays = event.tags
        .where(
          (t) =>
              t.isNotEmpty &&
              t[0] == 'r' &&
              (t.length == 2 || (t.length == 3 && t[2] != 'read')),
        )
        .map((t) => t[1])
        .toList();
    return relays.isNotEmpty ? relays : _defaultDmRelays;
  }
}
