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

### Prerequisites

- A configured [ndk](https://pub.dev/packages/ndk) instance with a logged-in account
- A sembast database instance for local storage
- A [sync_engine_shim_for_ndk](https://pub.dev/packages/sync_engine_shim_for_ndk) `SyncEngine`, which keeps the ndk cache filled from the relays
- A [blossom_cache](https://pub.dev/packages/blossom_cache) instance for large-email blobs

## Usage

### Initialize the client

```dart
import 'package:nostr_mail/nostr_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:sembast/sembast_io.dart' hide Filter;
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';

// Initialize ndk with your account. With a remote signer, prefer a cache
// manager that persists (`SembastCacheManager`): ndk keeps the plaintext it
// decrypted there, so approvals already granted are not asked for again.
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

// Local blob store for large emails on their way to Blossom. Use
// `idbFactoryBrowser` on web and `idbFactorySembastIo` on native.
final blossomCache = await IdbBlossomCache.open(factory: idbFactorySembastIo);

// Keeps the ndk cache in sync with the relays. Yours to own: the client
// starts it but never stops nor disposes it, so you can share it with your
// other ndk-based SDKs.
final syncEngine = SyncEngine(ndk, db: db);

// Create the client
final client = await NostrMailClient.create(
  ndk: ndk,
  db: db,
  blossomCache: blossomCache,
  syncEngine: syncEngine,
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
// Nothing has to be called to stay up to date: the sync engine keeps the ndk
// cache filled and revisits it every `maxStaleness` on its own, and the client
// declares what the active account needs, following logins and switches.

// Go to the relays now, however fresh the coverage is (pull to refresh).
await client.fetchRecent();

// Watch for new emails in real-time
client.watchInbox().listen((email) {
  print('New email from ${email.mime.fromEmail}: ${email.mime.decodeSubject()}');
});
```

### Manage local emails

```dart
// Get all cached emails (sorted by date, newest first)
final emails = await client.getEmails(limit: 20, offset: 0);

// Get a specific email by ID
final email = await client.getEmail('event-id');

// Search emails (globally across all folders)
final results = await client.search('meeting', limit: 10);

// Delete emails with one NIP-09 request
await client.delete(['event-id-1', 'event-id-2']);
```
