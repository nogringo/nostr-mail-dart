/// Where a delivery stands.
enum DeliveryStatus {
  /// Still being retried.
  pending,

  /// Reached at least one relay or server that counts.
  delivered,

  /// Every relay or server that counts refused it for good.
  failed,
}

/// How one relay answered an event, or one Blossom server a blob.
class UrlDelivery {
  final String url;
  final DeliveryStatus status;

  /// The refusal when [status] is [DeliveryStatus.failed], or the last error
  /// while it is still retried.
  final String? error;

  const UrlDelivery({required this.url, required this.status, this.error});
}

/// The blob holding an email too large to travel inline.
class BlobDelivery {
  final String sha256;

  /// The servers the recipient reads the blob from. Empty until the upload
  /// queue has resolved where the blob goes.
  final List<UrlDelivery> servers;

  const BlobDelivery({required this.sha256, required this.servers});

  /// Delivered once one server holds the blob, failed once every one refused.
  DeliveryStatus get status => _settle(servers.map((s) => s.status));
}

/// How far an email went for one recipient.
class RecipientDelivery {
  /// The Nostr recipient, the sender for its own copy, or a bridge.
  final String pubkey;

  /// The addresses a bridge relays to, empty for any other recipient.
  final List<String> smtpAddresses;

  /// The relays the recipient reads the email from.
  final List<UrlDelivery> relays;

  /// Null when the email travels inline.
  final BlobDelivery? blob;

  const RecipientDelivery({
    required this.pubkey,
    this.smtpAddresses = const [],
    required this.relays,
    this.blob,
  });

  bool get isBridge => smtpAddresses.isNotEmpty;

  /// Delivered once the recipient can read the email: one of its relays holds
  /// the event, and one of its servers the blob, if any.
  DeliveryStatus get status {
    final relayStatus = _settle(relays.map((r) => r.status));
    final blobStatus = blob?.status ?? DeliveryStatus.delivered;
    if (relayStatus == DeliveryStatus.failed ||
        blobStatus == DeliveryStatus.failed) {
      return DeliveryStatus.failed;
    }
    if (relayStatus == DeliveryStatus.pending ||
        blobStatus == DeliveryStatus.pending) {
      return DeliveryStatus.pending;
    }
    return DeliveryStatus.delivered;
  }
}

/// How far a Sent email went, recipient by recipient. Only the device that
/// sent it knows.
class EmailDelivery {
  final String emailId;

  /// Bcc included, bridges standing for the addresses they relay to.
  final List<RecipientDelivery> recipients;

  /// The sender's own copy, which its other devices read the email from.
  final RecipientDelivery? selfCopy;

  const EmailDelivery({
    required this.emailId,
    required this.recipients,
    this.selfCopy,
  });
}

DeliveryStatus _settle(Iterable<DeliveryStatus> statuses) {
  if (statuses.contains(DeliveryStatus.delivered)) {
    return DeliveryStatus.delivered;
  }
  if (statuses.contains(DeliveryStatus.pending) || statuses.isEmpty) {
    return DeliveryStatus.pending;
  }
  return DeliveryStatus.failed;
}
