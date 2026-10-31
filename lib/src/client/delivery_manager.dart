import 'package:blossom_upload_queue_shim_for_ndk/blossom_upload_queue_shim_for_ndk.dart';
import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:ndk/ndk.dart';
import 'package:rxdart/rxdart.dart';

import '../constants.dart';
import '../models/email_delivery.dart';
import '../storage/delivery_repository.dart';

/// Follows a Sent email through the broadcast and Blossom upload queues.
class DeliveryManager {
  final Ndk _ndk;
  final DeliveryRepository _repo;
  final OfflineBroadcast _broadcastQueue;
  final OfflineBlossomUpload _blossomUploadQueue;
  final List<String>? _defaultBlossomServers;

  DeliveryManager(
    this._ndk,
    this._repo,
    this._broadcastQueue,
    this._blossomUploadQueue, {
    this._defaultBlossomServers,
  });

  Stream<EmailDelivery?> watch(
    String emailId, {
    required String senderPubkey,
  }) async* {
    final targets = await _repo.getAll(emailId, senderPubkey: senderPubkey);
    if (targets.isEmpty) {
      yield null;
      return;
    }

    yield* CombineLatestStream.list([
      for (final target in targets)
        CombineLatestStream.combine2(
          _broadcastQueue.watch(target.eventId, pubkey: senderPubkey),
          target.blobSha256 == null
              ? Stream<QueuedBlobUpload?>.value(null)
              : _blossomUploadQueue.watch(
                  target.blobSha256!,
                  pubkey: senderPubkey,
                ),
          (broadcast, upload) => (target, broadcast, upload),
        ),
    ]).asyncMap((states) => _build(emailId, senderPubkey, states));
  }

  /// Pushes again every event and blob of [emailId] that some relay or server
  /// still owes.
  Future<void> retry(String emailId, {required String senderPubkey}) async {
    final targets = await _repo.getAll(emailId, senderPubkey: senderPubkey);
    for (final eventId in targets.map((t) => t.eventId).toSet()) {
      final broadcast = await _broadcastQueue.get(
        eventId,
        pubkey: senderPubkey,
      );
      if (broadcast != null && broadcast.status != BroadcastStatus.delivered) {
        await _broadcastQueue.rebroadcast(eventId, pubkey: senderPubkey);
      }
    }
    for (final sha256 in targets.map((t) => t.blobSha256).nonNulls.toSet()) {
      final upload = await _blossomUploadQueue.get(
        sha256,
        pubkey: senderPubkey,
      );
      if (upload != null && upload.status != BlobUploadStatus.delivered) {
        await _blossomUploadQueue.reupload(sha256, pubkey: senderPubkey);
      }
    }
  }

  Future<EmailDelivery?> _build(
    String emailId,
    String senderPubkey,
    List<(DeliveryTarget, QueuedBroadcast?, QueuedBlobUpload?)> states,
  ) async {
    final recipients = <RecipientDelivery>[];
    RecipientDelivery? selfCopy;
    for (final (target, broadcast, upload) in states) {
      // The queues were cleared under the record: nothing left to tell.
      if (broadcast == null) return null;
      if (target.blobSha256 != null && upload == null) return null;

      final recipient = RecipientDelivery(
        pubkey: target.recipientPubkey,
        smtpAddresses: target.smtpAddresses,
        relays: _relays(target.relays, broadcast),
        blob: upload == null
            ? null
            : BlobDelivery(
                sha256: upload.sha256,
                servers: await _servers(
                  upload,
                  readers: {senderPubkey, target.recipientPubkey},
                ),
              ),
      );
      if (target.recipientPubkey == senderPubkey) {
        selfCopy = recipient;
      } else {
        recipients.add(recipient);
      }
    }
    return EmailDelivery(
      emailId: emailId,
      recipients: recipients,
      selfCopy: selfCopy,
    );
  }

  List<UrlDelivery> _relays(List<String> relays, QueuedBroadcast broadcast) => [
    for (final url in relays.map(_normalize).toSet())
      if (broadcast.ackedRelays.contains(url))
        UrlDelivery(url: url, status: DeliveryStatus.delivered)
      else if (broadcast.terminalErrors[url] case final error?)
        UrlDelivery(url: url, status: DeliveryStatus.failed, error: error)
      else
        UrlDelivery(
          url: url,
          status: DeliveryStatus.pending,
          error: broadcast.lastErrors[url],
        ),
  ];

  /// The servers of [upload] that [readers] fetch the blob from: their own,
  /// and the defaults, as `fetchOrLoadEncryptedBlob` does.
  Future<List<UrlDelivery>> _servers(
    QueuedBlobUpload upload, {
    required Set<String> readers,
  }) async {
    final readable = {
      for (final pubkey in readers) ...await _blossomServersOf(pubkey),
      ...?_defaultBlossomServers,
      ...recommendedBlossomServers,
    }.map(_normalize).toSet();
    final counted = upload.servers.where(readable.contains).toList();
    // A server list missing from the cache must not leave the blob pending.
    final servers = counted.isEmpty ? upload.servers : counted;

    return [
      for (final url in servers)
        if (upload.ackedServers.contains(url))
          UrlDelivery(url: url, status: DeliveryStatus.delivered)
        else if (upload.rejectedServers[url] case final error?)
          UrlDelivery(url: url, status: DeliveryStatus.failed, error: error)
        else
          UrlDelivery(
            url: url,
            status: DeliveryStatus.pending,
            error: upload.lastErrors[url],
          ),
    ];
  }

  Future<List<String>> _blossomServersOf(String pubkey) async {
    final events = await _ndk.config.cache.loadEvents(
      pubKeys: [pubkey],
      kinds: [blossomServerListKind],
    );
    if (events.isEmpty) return const [];
    final latest = events.reduce((a, b) => a.createdAt >= b.createdAt ? a : b);
    return [
      for (final tag in latest.tags)
        if (tag.length > 1 && tag[0] == 'server') tag[1],
    ];
  }
}

/// How both queues store a URL, so ours compare with theirs.
String _normalize(String url) {
  var u = url.trim().toLowerCase();
  while (u.endsWith('/')) {
    u = u.substring(0, u.length - 1);
  }
  return u;
}
