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
