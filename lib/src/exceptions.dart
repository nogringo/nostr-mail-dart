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
