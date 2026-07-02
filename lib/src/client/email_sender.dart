import 'relay_resolver.dart';
import 'dart:convert';
import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:blossom_upload_queue_shim_for_ndk/blossom_upload_queue_shim_for_ndk.dart';
import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';

import '../constants.dart';
import '../exceptions.dart';
import '../models/email.dart';
import '../models/recipient.dart';
import '../services/bridge_resolver.dart';
import '../services/email_parser.dart';
import '../storage/email_repository.dart';
import '../utils/attachment_extractor.dart';
import '../utils/email_record_builder.dart';
import '../utils/encrypt_blob.dart';
import '../utils/mime_message_cleaner.dart';
import 'settings_manager.dart';
import 'email_delivery.dart';

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

  /// Build and send an email to already-resolved [Recipient]s.
  ///
  /// Each recipient is an explicit [NostrRecipient] or [SmtpRecipient], so there
  /// is no in-send NIP-05 guessing. Use [resolveRecipient] to turn a raw address
  /// into a [Recipient].
  Future<void> send({
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    required String subject,
    required String body,
    MailAddress? from,
    String? htmlBody,
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
  }) async {
    final message = await composeMime(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      from: from,
      htmlBody: htmlBody,
    );
    return sendMime(
      message,
      to: to,
      cc: cc,
      bcc: bcc,
      keepCopy: keepCopy,
      signRumor: signRumor,
      isPublic: isPublic,
    );
  }

  /// Compose the RFC 2822 MIME for an email, resolving the From identity the
  /// same way [send] does: explicit [from], else the first configured identity,
  /// else `<npub>@nostr`.
  Future<MimeMessage> composeMime({
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    required String subject,
    required String body,
    MailAddress? from,
    String? htmlBody,
  }) async {
    _assertPubkey();
    final senderPubkey = _pubkey!;

    final MailAddress finalFrom;
    if (from != null) {
      finalFrom = from;
    } else {
      final cached =
          _settings.cachedPrivateSettings ??
          await _settings.getPrivateSettings();
      if (cached?.identities != null && cached!.identities!.isNotEmpty) {
        finalFrom = cached.identities!.first;
      } else {
        final senderNpub = Nip19.encodePubKey(senderPubkey);
        finalFrom = MailAddress(null, '$senderNpub@nostr');
      }
    }

    List<MailAddress>? addresses(List<Recipient> rs) =>
        rs.isEmpty ? null : rs.map((r) => r.mailAddress).toList();

    final rawContent = _parser.build(
      from: finalFrom,
      to: to.map((r) => r.mailAddress).toList(),
      cc: addresses(cc),
      bcc: addresses(bcc),
      subject: subject,
      body: body,
      htmlBody: htmlBody,
    );

    return MimeMessage.parseFromText(rawContent);
  }

  /// Send a pre-constructed [MimeMessage] to already-resolved [Recipient]s.
  ///
  /// [to]/[cc]/[bcc] drive routing; the MIME headers drive only display and the
  /// relayed content. The grouping matters: a public email's To/Cc go in the
  /// public event while Bcc is gift-wrapped privately.
  Future<void> sendMime(
    MimeMessage message, {
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
  }) => _dispatch(
    message,
    to: to,
    cc: cc,
    bcc: bcc,
    keepCopy: keepCopy,
    signRumor: signRumor,
    isPublic: isPublic,
    mailFrom: mailFrom,
    delivery: BroadcastDelivery(_broadcastQueue, _buildGiftWrap),
  );

  /// Build every event this email would publish, dated at [rumorCreatedAt]
  /// (epoch seconds), without broadcasting. Hands the events to a scheduler so a
  /// DVM publishes them later. No local Sent copy is written; the sender's own
  /// gift wrap is among the returned events and lands in Sent via the normal
  /// sync once published.
  ///
  /// Also returns the sender's self-copy rumor: the full email as a kind:1301
  /// event, dated at the schedule time. The scheduler stores it as the package's
  /// display context, so a scheduled email is read back like any other email.
  Future<({List<OutgoingEvent> events, Nip01Event selfRumor})> buildOutgoing(
    MimeMessage message, {
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
    required int rumorCreatedAt,
  }) async {
    final delivery = ScheduleDelivery(rumorCreatedAt, _buildGiftWrap);
    final selfRumor = await _dispatch(
      message,
      to: to,
      cc: cc,
      bcc: bcc,
      keepCopy: keepCopy,
      signRumor: signRumor,
      isPublic: isPublic,
      mailFrom: mailFrom,
      delivery: delivery,
    );
    return (events: delivery.items, selfRumor: selfRumor);
  }

  Future<Nip01Event> _dispatch(
    MimeMessage message, {
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
    required Delivery delivery,
  }) async {
    _assertPubkey();
    final senderPubkey = _pubkey!;

    if (isPublic && !signRumor) {
      throw NostrMailException(
        'Public emails must be signed (signRumor must be true)',
      );
    }

    if (to.isEmpty && cc.isEmpty && bcc.isEmpty) {
      throw NostrMailException('No recipients provided');
    }

    final fromAddress = message.fromEmail;

    Set<String> nostrPubkeys(List<Recipient> rs) =>
        rs.whereType<NostrRecipient>().map((r) => r.pubkey).toSet();
    final toNostr = nostrPubkeys(to);
    final ccNostr = nostrPubkeys(cc);
    final bccNostr = nostrPubkeys(bcc);

    // Every legacy recipient is relayed through the sender's own bridge
    // (_smtp@<sender-domain>), resolved once here. Deterministic, not a guess:
    // the caller already told us which recipients are SMTP.
    final smtpEmails = [
      ...to,
      ...cc,
      ...bcc,
    ].whereType<SmtpRecipient>().map((r) => r.email).toList();
    final rcptToByBridge = <String, List<String>>{};
    if (smtpEmails.isNotEmpty) {
      if (fromAddress == null || !fromAddress.contains('@')) {
        throw NostrMailException(
          'A from address with a domain is required to relay to legacy '
          'recipients',
        );
      }
      final bridgePubkey = await BridgeResolver(
        ndk: _ndk,
        nip05Overrides: nip05Overrides,
      ).resolveBridgePubkey(fromAddress.split('@').last);
      rcptToByBridge[bridgePubkey] = smtpEmails;
    }

    // Nostr recipients drive the public event / direct gift wraps; bridges are
    // served separately by _publishToBridges, so they never enter these sets.
    final recipientPubkeys = {
      ...toNostr,
      ...ccNostr,
      ...bccNostr,
      ...rcptToByBridge.keys,
    };
    final publicRecipientPubkeys = {...toNostr, ...ccNostr};
    final bccRecipientPubkeys = {...bccNostr};

    final rawContent = message.renderMessage();
    final rawContentBytes = utf8.encode(rawContent);

    final targetPubkeys = {...toNostr, ...ccNostr, ...bccNostr};
    if (keepCopy) targetPubkeys.add(senderPubkey);

    // The self-copy rumor is always built (it is the scheduler's display
    // context and the future Sent copy); only its delivery is gated on keepCopy.
    late final Nip01Event senderRumor;

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

      // The queue reads bytes from the cache when it actually uploads, so
      // the blob has to be there before we enqueue.
      final descriptor = await _blossomCache.put(
        encryptedBlob.bytes,
        type: 'application/octet-stream',
      );
      final sha256Hash = descriptor.sha256;
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
        createdAt: delivery.rumorCreatedAt,
      );

      final signedPublicEvent = await _ndk.accounts.sign(emailEvent);

      final writeRelays = await _relays.getWriteRelays(senderPubkey);

      // Persist the sender's local copy before any broadcast is enqueued.
      // From here on every step is either a local write or a durable
      // enqueue, so a crash between save and broadcast cannot leave the
      // user without a Sent entry.
      final senderTags = List<List<String>>.from(baseTags)
        ..add(['p', senderPubkey]);
      final senderEmailEvent = Nip01Event(
        pubKey: senderPubkey,
        kind: emailKind,
        tags: senderTags,
        content: rawContent,
        createdAt: delivery.rumorCreatedAt,
      );
      senderRumor = signRumor
          ? await _ndk.accounts.sign(senderEmailEvent)
          : senderEmailEvent;

      if (keepCopy && delivery.saveSelfCopy) {
        await _saveSelfCopy(
          rumor: senderRumor,
          mimeContent: rawContent,
          senderPubkey: senderPubkey,
          isPublic: true,
        );
      }

      await delivery.deliverEvent(signedPublicEvent, writeRelays);

      final bccTags = List<List<String>>.from(baseTags)
        ..add(['public-ref', signedPublicEvent.id, ...writeRelays]);

      final bccRumor = Nip01Event(
        pubKey: senderPubkey,
        kind: emailKind,
        tags: bccTags,
        content: finalContent,
        createdAt: delivery.rumorCreatedAt,
      );

      final signedBccRumor = await _ndk.accounts.sign(bccRumor);

      final bccFutures = bccRecipientPubkeys.map((pubkey) async {
        await delivery.deliverGiftWrap(signedBccRumor, pubkey);
      });

      if (keepCopy) {
        await delivery.deliverGiftWrap(senderRumor, senderPubkey);
      }

      await Future.wait(bccFutures);
    } else {
      // Build and persist the sender's local copy before any broadcast.
      // Every network-required step (recipient resolution, Blossom server
      // lookup) has already succeeded by this point — anything past here
      // is a local write or a durable enqueue. Saving up-front guarantees
      // the email lands in the local Sent folder even if a per-recipient
      // sign call fails inside the parallel publish below.
      final senderContent = utf8.encode(rawContent).length < maxInlineSize
          ? rawContent
          : content;
      final senderTags = List<List<String>>.from(baseTags)
        ..insert(0, ['p', senderPubkey]);
      final senderEvent = Nip01Event(
        pubKey: senderPubkey,
        kind: emailKind,
        tags: senderTags,
        content: senderContent,
        createdAt: delivery.rumorCreatedAt,
      );
      senderRumor = signRumor
          ? await _ndk.accounts.sign(senderEvent)
          : senderEvent;
      if (keepCopy && delivery.saveSelfCopy) {
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
          await delivery.deliverGiftWrap(senderRumor, pubkey);
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
          createdAt: delivery.rumorCreatedAt,
        );

        final eventToPublish = signRumor
            ? await _ndk.accounts.sign(emailEvent)
            : emailEvent;

        await delivery.deliverGiftWrap(eventToPublish, pubkey);
      });

      await Future.wait(sendFutures);
    }

    // A legacy recipient is always reached the same way, public or not: a gift
    // wrap to its bridge carrying the SMTP envelope.
    await _publishToBridges(
      senderPubkey: senderPubkey,
      rcptToByBridge: rcptToByBridge,
      fromAddress: fromAddress,
      explicitMailFrom: mailFrom,
      baseTags: baseTags,
      rawContent: rawContent,
      largeEmailContent: content,
      signRumor: signRumor,
      delivery: delivery,
    );

    return senderRumor;
  }

  /// Send each SMTP bridge a gift-wrapped rumor with the envelope it relays on:
  /// `mail-from` (the sender) and one `rcpt-to` per legacy recipient. Runs for
  /// public and private emails alike - a bridge is always reached by gift wrap.
  Future<void> _publishToBridges({
    required String senderPubkey,
    required Map<String, List<String>> rcptToByBridge,
    required String? fromAddress,
    required String? explicitMailFrom,
    required List<List<String>> baseTags,
    required String rawContent,
    required String largeEmailContent,
    required bool signRumor,
    required Delivery delivery,
  }) async {
    if (rcptToByBridge.isEmpty) return;

    final bridgeMime = removeBccHeaders(rawContent);
    final bridgeContent = utf8.encode(bridgeMime).length < maxInlineSize
        ? bridgeMime
        : largeEmailContent;

    final futures = rcptToByBridge.entries.map((entry) async {
      final bridgePubkey = entry.key;
      final tags = List<List<String>>.from(baseTags)
        ..insert(0, ['p', bridgePubkey]);
      // `explicitMailFrom` is the inbound relay's sender; outbound we synthesise
      // mail-from from the sender's own address.
      if (explicitMailFrom == null && fromAddress != null) {
        tags.add(['mail-from', fromAddress]);
      }
      for (final rcptTo in entry.value) {
        tags.add(['rcpt-to', rcptTo]);
      }
      final event = Nip01Event(
        pubKey: senderPubkey,
        kind: emailKind,
        tags: tags,
        content: bridgeContent,
        createdAt: delivery.rumorCreatedAt,
      );
      final rumor = signRumor ? await _ndk.accounts.sign(event) : event;
      await delivery.deliverGiftWrap(rumor, bridgePubkey);
    });
    await Future.wait(futures);
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
    final extracted = await extractAttachments(
      mime: mimeMessage,
      cache: _blossomCache,
    );
    final email = Email(
      id: rumor.id,
      senderPubkey: senderPubkey,
      recipientPubkey: senderPubkey,
      lightMimeText: extracted.lightMimeText,
      attachmentRefs: extracted.refs,
      blossomHash: rumor.getFirstTag('x'),
      decryptionKey: rumor.getFirstTag('decryption-key'),
      decryptionNonce: rumor.getFirstTag('decryption-nonce'),
      createdAt: DateTime.fromMillisecondsSinceEpoch(rumor.createdAt * 1000),
      isPublic: isPublic,
      // Per nostr-mail-core spec: bridged when the rumor carries mail-from.
      isBridged: rumor.getFirstTag('mail-from') != null,
      mimeMessage: mimeMessage,
    );
    final record = buildEmailRecord(email: email, folder: 'sent');
    await _emailRepo.save(record);
  }

  Future<OutgoingEvent> _buildGiftWrap(
    Nip01Event rumor,
    String recipientPubkey,
  ) async {
    final giftWrapEvent = await _ndk.giftWrap.toGiftWrap(
      rumor: rumor,
      recipientPubkey: recipientPubkey,
    );
    // Gift wraps go to the recipient's DM relays (NIP-17). For a scheduled send
    // the rumor is dated at the schedule time; ndk randomizes the seal and gift
    // wrap in the 2 days before it, so the envelope never reveals the email was
    // pre-built.
    final dmRelays = await _relays.getDmRelays(recipientPubkey);
    return OutgoingEvent(giftWrapEvent, dmRelays);
  }
}
