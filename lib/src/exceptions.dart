import 'models/recipient.dart';

class NostrMailException implements Exception {
  final String message;
  NostrMailException(this.message);

  @override
  String toString() => 'NostrMailException: $message';
}

class BridgeResolutionException extends NostrMailException {
  BridgeResolutionException(String domain)
    : super('Failed to resolve bridge for domain: $domain');
}

class RecipientResolutionException extends NostrMailException {
  RecipientResolutionException(String recipient)
    : super('Failed to resolve recipient: $recipient');
}

/// Thrown by a send, before anything is saved or enqueued, when some of its
/// targets publish no relay to receive on: neither a DM relay list (kind
/// 10050) nor NIP-65 read relays.
class UnreachableRecipientsException extends NostrMailException {
  /// An SMTP recipient is here when its bridge is unreachable.
  final List<Recipient> recipients;

  /// Whether the sender's own copy has nowhere to go.
  final bool sender;

  UnreachableRecipientsException(this.recipients, {this.sender = false})
    : super('No relay to reach ${_describe(recipients, sender)}');

  static String _describe(List<Recipient> recipients, bool sender) => [
    for (final r in recipients) r.mailAddress.email,
    if (sender) 'the sender',
  ].join(', ');
}

class EmailParseException extends NostrMailException {
  EmailParseException(String details)
    : super('Failed to parse email: $details');
}

class RelayException extends NostrMailException {
  RelayException(String details) : super('Relay error: $details');
}

/// Thrown when an operation cannot proceed because a required network call
/// failed for connectivity reasons (DNS, socket, timeout, offline transport).
///
/// The UI should treat this as "ask the user to reconnect, then retry."
/// It is intentionally distinct from [BridgeResolutionException] and
/// [RecipientResolutionException], which signal that the lookup itself
/// produced a definitive negative answer (the relay/server is reachable
/// and replied "no such name").
///
/// [operation] identifies the call site (`nip05`, `bridge`, …) so the UI
/// can tailor the message without parsing strings.
class NetworkRequiredException extends NostrMailException {
  final String operation;
  NetworkRequiredException(this.operation, String details)
    : super('Network required for $operation: $details');
}
