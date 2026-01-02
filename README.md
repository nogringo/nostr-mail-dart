# nostr_mail

A Dart SDK for sending and receiving emails over the Nostr protocol using NIP-59 gift-wrapped messages.

## Features

- Send emails to Nostr users (via npub, hex pubkey, or NIP-05 identifier)
- Send emails to legacy email addresses via SMTP bridges
- Receive and decrypt gift-wrapped email messages
- Local email storage with sembast
- RFC 2822 email format support
- NIP-05 identity resolution
- Automatic relay discovery (NIP-65)

## Getting Started

### Installation

Add to your `pubspec.yaml`:

```yaml
dependencies:
  nostr_mail: ^1.0.0
```

### Prerequisites

- A configured [ndk](https://pub.dev/packages/ndk) instance with a logged-in account
- A sembast database instance for local storage

## Usage

### Initialize the client

```dart
import 'package:nostr_mail/nostr_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:sembast/sembast_io.dart';

// Initialize ndk with your account
final ndk = Ndk(NdkConfig(
  cache: MemCacheManager(),
  eventVerifier: Bip340EventVerifier(),
));
final keyPair = Bip340.generatePrivateKey();
ndk.accounts.loginPrivateKey(
  pubkey: keyPair.publicKey,
  privkey: keyPair.privateKey!,
);

// Open a database for local storage
final db = await databaseFactoryIo.openDatabase('emails.db');

// Create the client
final client = NostrMailClient(
  ndk: ndk,
  db: db,
);
```

### Send an email

```dart
// Send to a Nostr user (npub, hex pubkey, or NIP-05)
await client.send(
  to: 'npub1xyz...', // or 'user@example.com' for NIP-05
  subject: 'Hello from Nostr!',
  body: 'This is a test email sent over Nostr.',
);

// Send to a legacy email (routed via bridge)
await client.send(
  to: 'someone@gmail.com',
  subject: 'Hello!',
  body: 'This email will be delivered via SMTP bridge.',
);
```

### Receive emails

```dart
// Sync historical emails from relays
await client.sync();

// Watch for new emails in real-time
client.watchInbox().listen((email) {
  print('New email from ${email.from}: ${email.subject}');
});
```

### Manage local emails

```dart
// Get all cached emails (sorted by date, newest first)
final emails = await client.getEmails(limit: 20, offset: 0);

// Get a specific email by ID
final email = await client.getEmail('event-id');

// Delete an email
await client.delete('event-id');
```
