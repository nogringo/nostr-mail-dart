import 'dart:convert';
import 'dart:typed_data';

import 'package:blossom_cache/blossom_cache.dart';
import 'package:blossom_upload_queue_shim_for_ndk/blossom_upload_queue_shim_for_ndk.dart';
import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:nostr_event_scheduler/nostr_event_scheduler.dart' as scheduler;

import '../constants.dart';
import '../exceptions.dart';
import '../models/email.dart';
import '../models/scheduled_email.dart';
import '../services/email_parser.dart';
import '../storage/email_repository.dart';
import '../utils/attachment_extractor.dart';
import '../utils/email_record_builder.dart';
import '../utils/encrypt_blob.dart';
import '../utils/mime_message_cleaner.dart';
import '../utils/recipient_resolver.dart';
import 'relay_resolver.dart';
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
  final scheduler.EventScheduler _scheduler;
  final SchedulerDvmConfig? _schedulerDvm;
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
    required scheduler.EventScheduler scheduler,
    SchedulerDvmConfig? schedulerDvm,
    List<String>? defaultBlossomServers,
    this.nip05Overrides,
  }) : _scheduler = scheduler,
       _schedulerDvm = schedulerDvm,
       _parser = EmailParser(),
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
    DateTime? scheduledAt,
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

    final rawContent = _parser.build(
      from: finalFrom,
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      htmlBody: htmlBody,
      date: scheduledAt,
    );

    final message = MimeMessage.parseFromText(rawContent);
    return sendMime(
      message,
      keepCopy: keepCopy,
      signRumor: signRumor,
      isPublic: isPublic,
      scheduledAt: scheduledAt,
    );
  }

  /// Send a pre-constructed [MimeMessage].
  Future<void> sendMime(
    MimeMessage message, {
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
    DateTime? scheduledAt,
  }) async {
    _assertPubkey();

    if (isPublic && !signRumor) {
      throw NostrMailException(
        'Public emails must be signed (signRumor must be true)',
      );
    }

    if (scheduledAt != null) {
      if (!scheduledAt.isAfter(DateTime.now())) {
        throw NostrMailException('scheduledAt must be in the future');
      }
      if (_schedulerDvm == null) {
        throw NostrMailException(
          'schedulerDvm must be configured to schedule emails',
        );
      }
      message.setHeader('Date', DateCodec.encodeDate(scheduledAt));
    }

    final delivery = await _prepareDelivery(
      message,
      keepCopy: keepCopy,
      signRumor: signRumor,
      isPublic: isPublic,
      mailFrom: mailFrom,
      eventCreatedAt: scheduledAt,
      saveSelfCopyImmediately: scheduledAt == null,
    );

    if (scheduledAt == null) {
      await _broadcastDelivery(delivery);
    } else {
      await _scheduleDelivery(delivery, scheduledAt);
    }
  }

  Future<_PreparedDelivery> _prepareDelivery(
    MimeMessage message, {
    required bool keepCopy,
    required bool signRumor,
    required bool isPublic,
    required String? mailFrom,
    required DateTime? eventCreatedAt,
    required bool saveSelfCopyImmediately,
  }) async {
    final senderPubkey = _pubkey!;
    final createdAtSeconds = eventCreatedAt == null
        ? 0
        : eventCreatedAt.millisecondsSinceEpoch ~/ 1000;

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
        ndk: _ndk,
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

    final targets = <_PreparedTarget>[];
    Nip01Event? selfCopyRumor;
    final manifestEmailEvent = Nip01Event(
      pubKey: senderPubkey,
      kind: emailKind,
      tags: List<List<String>>.from(baseTags)..insert(0, ['p', senderPubkey]),
      content: rawContentBytes.length < maxInlineSize ? rawContent : content,
      createdAt: createdAtSeconds,
    );

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
        createdAt: createdAtSeconds,
      );

      final signedPublicEvent = await _ndk.accounts.sign(emailEvent);

      final writeRelays = await _relays.getWriteRelays(senderPubkey);
      targets.add(
        _PreparedTarget(event: signedPublicEvent, relays: writeRelays),
      );

      if (keepCopy) {
        final senderTags = List<List<String>>.from(baseTags)
          ..add(['p', senderPubkey]);

        final senderEmailEvent = Nip01Event(
          pubKey: senderPubkey,
          kind: emailKind,
          tags: senderTags,
          content: rawContent,
          createdAt: createdAtSeconds,
        );

        selfCopyRumor = signRumor
            ? await _ndk.accounts.sign(senderEmailEvent)
            : senderEmailEvent;
        if (saveSelfCopyImmediately) {
          await _saveSelfCopy(
            rumor: selfCopyRumor,
            mimeContent: rawContent,
            senderPubkey: senderPubkey,
            isPublic: true,
          );
        }
      }

      final bccTags = List<List<String>>.from(baseTags)
        ..add(['public-ref', signedPublicEvent.id, ...writeRelays]);

      final bccRumor = Nip01Event(
        pubKey: senderPubkey,
        kind: emailKind,
        tags: bccTags,
        content: finalContent,
        createdAt: createdAtSeconds,
      );

      if (bccRecipientPubkeys.isNotEmpty) {
        final signedBccRumor = await _ndk.accounts.sign(bccRumor);
        for (final pubkey in bccRecipientPubkeys) {
          targets.add(
            await _prepareGiftWrapTarget(
              signedBccRumor,
              pubkey,
              eventCreatedAt: eventCreatedAt,
            ),
          );
        }
      }

      if (selfCopyRumor != null) {
        targets.add(
          await _prepareGiftWrapTarget(
            selfCopyRumor,
            senderPubkey,
            eventCreatedAt: eventCreatedAt,
          ),
        );
      }
    } else {
      final targetPubkeys = <String>{...recipientPubkeys};
      if (keepCopy) targetPubkeys.add(senderPubkey);

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
          createdAt: createdAtSeconds,
        );
        selfCopyRumor = signRumor
            ? await _ndk.accounts.sign(senderEvent)
            : senderEvent;
        if (saveSelfCopyImmediately) {
          await _saveSelfCopy(
            rumor: selfCopyRumor,
            mimeContent: rawContent,
            senderPubkey: senderPubkey,
            isPublic: false,
          );
        }
      }

      for (final pubkey in targetPubkeys) {
        // Reuse the pre-built sender rumor so rumor.id stays stable:
        // when the gift wrap comes back via sync, the dedup is a no-op.
        if (keepCopy && pubkey == senderPubkey) {
          targets.add(
            await _prepareGiftWrapTarget(
              selfCopyRumor!,
              pubkey,
              eventCreatedAt: eventCreatedAt,
            ),
          );
          continue;
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
          createdAt: createdAtSeconds,
        );

        final eventToPublish = signRumor
            ? await _ndk.accounts.sign(emailEvent)
            : emailEvent;

        targets.add(
          await _prepareGiftWrapTarget(
            eventToPublish,
            pubkey,
            eventCreatedAt: eventCreatedAt,
          ),
        );
      }
    }

    return _PreparedDelivery(
      rawContent: rawContent,
      senderPubkey: senderPubkey,
      isPublic: isPublic,
      selfCopySaved: saveSelfCopyImmediately,
      selfCopyRumor: selfCopyRumor,
      manifestEmailEvent: manifestEmailEvent,
      targets: targets,
    );
  }

  Future<void> _broadcastDelivery(_PreparedDelivery delivery) async {
    if (delivery.selfCopyRumor != null && !delivery.selfCopySaved) {
      await _saveSelfCopy(
        rumor: delivery.selfCopyRumor!,
        mimeContent: delivery.rawContent,
        senderPubkey: delivery.senderPubkey,
        isPublic: delivery.isPublic,
      );
    }

    await Future.wait(
      delivery.targets.map(
        (target) =>
            _broadcastQueue.broadcast(target.event, relays: target.relays),
      ),
    );
  }

  Future<void> _scheduleDelivery(
    _PreparedDelivery delivery,
    DateTime scheduledAt,
  ) async {
    final dvm = _schedulerDvm!;
    final items = delivery.targets
        .map(
          (target) => scheduler.SchedulePackageItem(
            event: target.event,
            dvmPubkey: dvm.pubkey,
            at: scheduledAt,
            relays: target.relays,
            dvmReadRelays: dvm.readRelays,
          ),
        )
        .toList();

    await _scheduler.schedulePackage(
      items,
      content: scheduledEmailPackageContent(delivery.manifestEmailEvent),
    );
  }

  Future<_PreparedTarget> _prepareGiftWrapTarget(
    Nip01Event rumor,
    String recipientPubkey, {
    required DateTime? eventCreatedAt,
  }) async {
    final giftWrapEvent = await _buildGiftWrap(
      rumor,
      recipientPubkey,
      eventCreatedAt: eventCreatedAt,
    );
    final dmRelays = await _relays.getDmRelays(recipientPubkey);
    return _PreparedTarget(event: giftWrapEvent, relays: dmRelays);
  }

  Future<Nip01Event> _buildGiftWrap(
    Nip01Event rumor,
    String recipientPubkey, {
    required DateTime? eventCreatedAt,
  }) async {
    if (eventCreatedAt == null) {
      return _ndk.giftWrap.toGiftWrap(
        rumor: rumor,
        recipientPubkey: recipientPubkey,
      );
    }

    final signer = _ndk.accounts.getLoggedAccount()?.signer;
    if (signer == null) {
      throw NostrMailException('No account configured in ndk');
    }

    final createdAt = eventCreatedAt.millisecondsSinceEpoch ~/ 1000;
    final encryptedRumor = await signer.encryptNip44(
      plaintext: Nip01EventModel.fromEntity(rumor).toJsonString(),
      recipientPubKey: recipientPubkey,
    );
    if (encryptedRumor == null) {
      throw NostrMailException('Failed to encrypt scheduled email seal');
    }

    final seal = await signer.sign(
      Nip01Event(
        pubKey: signer.getPublicKey(),
        kind: 13,
        tags: const [],
        content: encryptedRumor,
        createdAt: createdAt,
      ),
    );

    final ephemeralSigner = _ndk.giftWrap.eventSignerFactory
        .createWithNewKeyPair();
    final encryptedSeal = await ephemeralSigner.encryptNip44(
      plaintext: Nip01EventModel.fromEntity(seal).toJsonString(),
      recipientPubKey: recipientPubkey,
    );
    if (encryptedSeal == null) {
      throw NostrMailException('Failed to encrypt scheduled email gift wrap');
    }

    return ephemeralSigner.sign(
      Nip01Event(
        pubKey: ephemeralSigner.getPublicKey(),
        kind: giftWrapKind,
        tags: [
          ['p', recipientPubkey],
        ],
        content: encryptedSeal,
        createdAt: createdAt,
      ),
    );
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
}

class _PreparedDelivery {
  final String rawContent;
  final String senderPubkey;
  final bool isPublic;
  final bool selfCopySaved;
  final Nip01Event? selfCopyRumor;
  final Nip01Event manifestEmailEvent;
  final List<_PreparedTarget> targets;

  _PreparedDelivery({
    required this.rawContent,
    required this.senderPubkey,
    required this.isPublic,
    required this.selfCopySaved,
    required this.selfCopyRumor,
    required this.manifestEmailEvent,
    required this.targets,
  });
}

class _PreparedTarget {
  final Nip01Event event;
  final List<String> relays;

  _PreparedTarget({required this.event, required this.relays});
}
