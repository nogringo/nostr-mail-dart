/// Dart SDK for email over Nostr.
///
/// Send and receive emails via Nostr using NIP-59 gift-wrapped messages.
///
/// Supports both inline emails (< 32KB) and large emails via Blossom storage.
library;

export 'src/client.dart' show NostrMailClient;
export 'src/constants.dart';
export 'src/models/email.dart' show Email;
export 'src/models/encrypted_blob.dart';
export 'src/models/mail_event.dart';
export 'src/models/private_settings.dart' show PrivateSettings;
export 'src/services/email_parser.dart' show EmailParser;
export 'src/utils/event_email_parser.dart' show parseEmailEvent;
export 'src/exceptions.dart';
