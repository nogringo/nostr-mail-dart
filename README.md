# nostr_mail

A Dart SDK for sending and receiving emails over the Nostr protocol using NIP-59 gift-wrapped messages.

## Features

- Send emails to Nostr users (via npub, hex pubkey, or NIP-05 identifier)
- Send emails to legacy email addresses via SMTP bridges
- Receive and decrypt gift-wrapped email messages
- Local email storage with drift (SQLite), full-text search with FTS5
- RFC 2822 email format support
- NIP-05 identity resolution
- Automatic relay discovery (NIP-65)

## Getting Started

### Prerequisites

- A configured [ndk](https://pub.dev/packages/ndk) instance with a logged-in account
- A `NostrMailDatabase` (drift) for the mail store, opened with `NativeDatabase` on native or `WasmDatabase` on web
- A sembast database instance, shared by the broadcast queue, the Blossom upload queue, the event scheduler and the sync engine
- A [sync_engine_shim_for_ndk](https://pub.dev/packages/sync_engine_shim_for_ndk) `SyncEngine`, which keeps the ndk cache filled from the relays
- A [blossom_cache](https://pub.dev/packages/blossom_cache) instance for large-email blobs

## Usage

### Initialize the client

```dart
import 'dart:io';

import 'package:drift/native.dart';
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

// The mail store. Yours to close, after `client.dispose()`.
final database = NostrMailDatabase(NativeDatabase(File('nostr_mail.sqlite')));

// The sembast database the queues, the scheduler and the sync engine share.
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
  database: database,
  db: db,
  blossomCache: blossomCache,
  syncEngine: syncEngine,
);
```

#### On the web

Copy `sqlite3.wasm` (from the [sqlite3.dart](https://github.com/simolus3/sqlite3.dart/releases) release matching your resolved `sqlite3` version) and `drift_worker.js` (from the [drift](https://github.com/simolus3/drift/releases) release matching `drift`) into your `web/` folder, then open the store through a worker:

```dart
import 'package:drift/wasm.dart';

final result = await WasmDatabase.open(
  databaseName: 'nostr_mail',
  sqlite3Uri: Uri.parse('sqlite3.wasm'),
  driftWorkerUri: Uri.parse('drift_worker.js'),
);
final database = NostrMailDatabase(result.resolvedExecutor);
```

Check `result.chosenImplementation`: drift stores the file in OPFS when the browser allows it (`opfsShared` needs no headers on Chrome and Firefox; `opfsLocks` needs the page to be cross-origin isolated, which is what Safari falls back to). Otherwise it falls back to IndexedDB, which works but keeps the file image in memory.

Note that a `SembastCacheManager` given to ndk holds every raw event in memory too. With a large mailbox that cache, not the mail store, is where the memory goes.

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

### List a mailbox

`getSummaries` is what a message list should call. It reads only the indexed
columns a row draws, so it never touches the stored MIME nor parses it.

```dart
final page = await client.getSummaries(
  folder: 'inbox',
  limit: 50,
  offset: 0,
);

print('${page.items.length} of ${page.total}');
if (page.hasMore) {
  // fetch the next page with offset: page.offset + page.items.length
}

for (final row in page.items) {
  print('${row.isRead ? ' ' : '*'} ${row.isStarred ? '★' : ' '} '
      '${row.fromName ?? row.from}: ${row.subject}');
  print('  ${row.preview}');
  if (row.hasAttachments) {
    print('  ${row.attachmentRefs.map((a) => a.filename).join(', ')}');
  }
}
```

A row also carries `to`, `cc`, `bcc`, `date`, `folder`, `labels`, `isPublic`
and `isBridged`. For a native nostr sender, `from` is `<npub>@nostr` and the
real name lives in the profile behind `senderPubkey`: resolve that first and
fall back to `fromName ?? from`.

Load the whole message, body and MIME included, only when a row is opened:

```dart
final email = await client.getEmail(row.id);
```

### Manage local emails

```dart
// Get all cached emails (sorted by date, newest first). These carry the full
// message: prefer getSummaries above for anything list-shaped.
final emails = await client.getEmails(limit: 20, offset: 0);

// Get a specific email by ID
final email = await client.getEmail('event-id');

// Search emails (globally across all folders)
final results = await client.search('meeting', limit: 10);

// Delete emails with one NIP-09 request
await client.delete(['event-id-1', 'event-id-2']);
```
