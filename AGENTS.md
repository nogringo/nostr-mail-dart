# nostr_mail — Agent Guide

> Dart SDK for sending and receiving emails over the Nostr protocol using NIP-59 gift-wrapped messages.
> Version: 1.14.0 | Dart SDK: ^3.10.8 | Platforms: Android, iOS, Linux, macOS, Web, Windows

---

## Project Overview

`nostr_mail` is a pub.dev package that lets Nostr users send and receive RFC 2822 emails via the Nostr relay network. Emails are transported as **kind 1301** events inside **NIP-59 gift wraps (kind 1059)**. The SDK handles:

- Building & parsing MIME messages (`enough_mail_plus`)
- Recipient resolution (npub, hex pubkey, NIP-05, or legacy SMTP bridges)
- Local caching & search (`sembast` NoSQL database)
- Large-attachment offload to **Blossom** servers (AES-256-GCM encrypted blobs)
- Metadata labels (trash, archive, read, starred) via **NIP-32** (kind 1985)
- Cross-device private settings sync via **NIP-78** (kind 30078, NIP-44 encrypted)
- Public email posts (signed kind 1301, optionally with BCC gift wraps)
- Real-time inbox watching via unified `MailEvent` stream

### Key NIPs Implemented

| NIP | Purpose |
|-----|---------|
| NIP-01 | Base events, signatures |
| NIP-05 | Identity & bridge resolution (`_smtp@domain`) |
| NIP-09 | Deletion requests (emails & labels) |
| NIP-17 | DM relay lists (kind 10050) |
| NIP-18 | Generic reposts (kind 16) |
| NIP-32 | Labels (kind 1985, namespace `mail`) |
| NIP-44 | Encryption for private settings |
| NIP-59 | Gift wraps (kind 1059) & seals (kind 13) |
| NIP-65 | Write relay lists (kind 10002) |
| NIP-78 | App-specific data (kind 30078) |
| BUD-01/03 | Blossom blob storage |

---

## Build and Test Commands

```bash
# Install dependencies
dart pub get

# Static analysis (uses package:lints/recommended.yaml)
dart analyze

# Run all tests
dart test

# Run a specific test file
dart test test/nostr_mail_test.dart

# Verbose test output
dart test --reporter=expanded
```

### Known Test Behaviours

- **`test/cc_bcc_test.dart`** currently **fails** because it hard-codes `ws://localhost:7777` without starting a `MockRelay`. This is a known issue.
- **`test/blossom_integration_test.dart`** hits the **real internet** (live Blossom servers & relays). It can be slow (30–60 s) and flaky depending on network conditions.
- Most other integration tests spin up local `MockRelay` WebSocket servers and `MockBlossomServer` HTTP servers, so they are self-contained.
- Tests use **isolated in-memory Sembast database names** (`test_db_${DateTime.now().millisecondsSinceEpoch}` or a `dbCounter`) to avoid state bleeding between tests.

---

## Code Organization

```
lib/
├── nostr_mail.dart              # Public API exports
└── src/
    ├── client.dart              # NostrMailClient (~1800 lines) — core of the SDK
    ├── constants.dart           # Event kinds, namespaces, default relays/servers
    ├── exceptions.dart          # NostrMailException hierarchy
    ├── models/
    │   ├── email.dart           # Email model wrapping MimeMessage
    │   ├── mail_event.dart      # Sealed class: EmailReceived, LabelAdded, etc.
    │   ├── private_settings.dart# Cross-device settings (signature, bridges, identities)
    │   ├── encrypted_blob.dart  # AES-GCM blob metadata
    │   └── unwrapped_gift_wrap.dart # Seal + Rumor pair
    ├── services/
    │   ├── email_parser.dart    # RFC 2822 build / parse helpers
    │   └── bridge_resolver.dart # NIP-05 lookup for bridges & users
    ├── storage/
    │   ├── email_store.dart     # Sembast CRUD for emails
    │   ├── gift_wrap_store.dart # Tracks un/processed gift wraps
    │   ├── label_store.dart     # NIP-32 label CRUD
    │   └── private_settings_store.dart # Local decrypted settings cache
    └── utils/
        ├── event_email_parser.dart   # Parses kind 1301 → Email (inline or Blossom)
        ├── recipient_resolver.dart   # npub / hex / NIP-05 / bridge resolution
        ├── encrypt_blob.dart         # AES-256-GCM encryption
        ├── decrypt_blob.dart         # AES-256-GCM decryption
        ├── mime_message_cleaner.dart # removeBccHeaders()
        └── html_utils.dart           # stripHtmlTags()

test/
├── nostr_mail_test.dart         # Unit tests for models, parser, stores, resolver
├── mocks/
│   ├── mock_relay.dart          # Full WebSocket Nostr relay mock (~800 lines)
│   ├── mock_blossom_server.dart # Shelf-based Blossom server mock
│   └── mock_bridge.dart         # SMTP bridge simulator using NostrMailClient
├── models/
│   └── test_user.dart           # Helper: create user + NDK + in-memory DB
└── <feature>_test.dart          # Per-feature integration tests
```

---

## Public API Surface

Import everything via:

```dart
import 'package:nostr_mail/nostr_mail.dart';
```

### Main Class: `NostrMailClient`

```dart
NostrMailClient({
  required Ndk ndk,               // Configured ndk instance with logged-in account
  required Database db,           // Sembast database (memory or file)
  List<String>? defaultDmRelays,
  List<String>? defaultBlossomServers,
  Map<String, String>? nip05Overrides, // For testing / local resolution
})
```

**Lifecycle:**
- `sync()` — incremental sync using NDK `fetchedRanges` (gap-only fetching)
- `resync()` — full sync after clearing `fetchedRanges`
- `fetchRecent()` — simple parallel fetch without range optimization
- `watch()` — broadcast stream of `MailEvent` (emails, labels, deletions)
- `stopWatching()` — closes stream & subscriptions
- `clearAll()` — wipes local DBs and caches

**Sending:**
- `send({List<MailAddress> to, cc, bcc, required subject, required body, ...})`
- `sendMime(MimeMessage, ...)` — lower-level, resolves all recipients automatically
- `repost(Nip01Event)` — NIP-18 generic repost

**Reading:**
- `getEmails()`, `getInboxEmails()`, `getSentEmails()` — paginated, excludes trashed by default
- `getEmail(id)`, `search(query)`
- `getTrashedEmails()`, `getArchivedEmails()`, `getStarredEmails()`

**Labels (local-first):**
- `addLabel(emailId, label)`, `removeLabel(emailId, label)`
- Convenience: `moveToTrash`, `restoreFromTrash`, `moveToArchive`, `markAsRead`, `star`, etc.
- Labels are saved locally **immediately**, broadcast to relays in background.
- Folder labels (`folder:*`) are **mutually exclusive**.

**Private Settings (NIP-78):**
- `getPrivateSettings()` — fetch from relays, decrypt, cache
- `getCachedPrivateSettings()` / `cachedPrivateSettings` — read local cache (no signer needed)
- `setPrivateSettings()`, `updatePrivateSettings(...)` — encrypt & publish

**NIP-59 Introspection:**
- `getGiftWrap(emailId)`, `getSeal(emailId)`, `getRumor(emailId)`

---

## Testing Strategy & Conventions

1. **Unit tests** (`nostr_mail_test.dart`) — no network, use mocked `http.Client` via `mocktail`, use `databaseFactoryMemory` for Sembast.
2. **Integration tests with mocks** — start `MockRelay` / `MockBlossomServer`, create `TestUser` objects, send emails between them, assert on local DB state.
3. **Integration tests with real network** — `blossom_integration_test.dart` only; marked with long `Timeout`.
4. **State isolation** — always use unique DB names per test. Never reuse `'test_db'` strings.
5. **Tear-down pattern** for mock relays:
   ```dart
   final relay = MockRelay(name: 'relay');
   await relay.startServer();
   addTearDown(() async => relay.stopServer());
   ```
6. **TestUser helper** encapsulates key generation, NDK init, DB creation, and `NostrMailClient` instantiation.

### Running Tests Reliably

Because some tests connect to the public internet and others need a local relay, the suite is **not hermetic** as a whole. For CI or agent work:

```bash
# Fast, offline-only tests
dart test test/nostr_mail_test.dart
dart test test/bridges_test.dart
dart test test/folder_label_exclusion_test.dart

# Slow / network-dependent tests
dart test test/blossom_integration_test.dart   # can fail on bad connectivity
dart test test/cc_bcc_test.dart                # currently broken (no mock relay started)
```

---

## Code Style Guidelines

- Lint rules: `analysis_options.yaml` includes `package:lints/recommended.yaml`.
- One analyzer override: `experimental_member_use: ignore`.
- Use `library;` doc comments at the top of library files.
- Prefer named parameters for public APIs.
- Use `Future.wait([...])` and `.wait` (Dart 3 record destructuring) for parallel async work.
- Store raw RFC 2822 MIME in `Email.rawContent`; parse on demand via `enough_mail_plus`.
- Equality on `Email` is **identity-based on `id`** only.

---

## Security Considerations

- **Gift wraps** are decrypted with the NDK signer. If the signer is a remote bunker (NIP-46) and offline, decryption fails gracefully; events remain unprocessed and can be retried via `retry(eventId)`.
- **BCC privacy**: `removeBccHeaders()` strips `Bcc:` and `Resent-Bcc:` from MIME before sending to anyone except the sender (when `keepCopy == true`).
- **Large emails**: Content > 32 KB is uploaded to Blossom as an AES-256-GCM encrypted blob. The event then contains only the SHA-256 hash, key, and nonce.
- **Private settings**: Stored as NIP-78 replaceable events encrypted to self with NIP-44. Decrypted JSON is cached locally so the app can read settings without waking the bunker.
- **Public emails**: Must be signed (`signRumor = true`). BCC recipients of public emails receive a **shared signed rumor** gift-wrapped individually, with a `public-ref` tag pointing to the public event.

---

## Important Implementation Details

### Inline vs Blossom Threshold
`maxInlineSize = 32768` bytes. NIP-44 plaintext limit is 65,535 bytes, but NIP-59 double-wrapping (Rumor → Seal → Gift Wrap) expands the payload via Base64 + padding. 32 KB is the safe threshold.

### Relay Selection
- **DM relays**: read from NIP-17 kind 10050 event; fallback to `recommendedDmRelays`.
- **Write relays**: read from NIP-65 kind 10002 event; fallback to `recommendedDmRelays`.
- Both lists are fetched on-demand; there is **no in-memory cache** for relay lists yet (see `TODO.md`).

### FetchedRanges (Gap Sync)
The client relies on NDK's `fetchedRanges` to avoid re-downloading already-synced time ranges. `sync()` only fills gaps. `resync()` clears ranges and starts over. `fetchRecent()` bypasses range optimization entirely.

### Label Event Format (NIP-32)
```json
{
  "kind": 1985,
  "tags": [
    ["L", "mail"],
    ["l", "folder:trash", "mail"],
    ["e", "<email_id>", "", "labelled"]
  ],
  "content": ""
}
```
Removal is a NIP-09 kind 5 deletion request targeting the label event ID.

### `Email.isBridged`
An email is considered "bridged" if the sender's pubkey does **not** match the pubkey extracted from the `From:` address local part. This detects legacy SMTP-to-Nostr gateway traffic.

---

## Files to Know

| File | Why it matters |
|------|----------------|
| `lib/src/client.dart` | The entire business logic lives here. |
| `lib/src/constants.dart` | All event kinds and protocol magic values. |
| `email-labels.md` | Formal spec for NIP-32 label usage in this project. |
| `TODO.md` | Roadmap: local-first sync queue, label cleanup, performance caching. |
| `CHANGELOG.md` | Detailed per-version breaking changes and new features. |
| `test/mocks/mock_relay.dart` | Very capable Nostr relay mock; reusable for any NDK-based test. |

---

## When Modifying This Codebase

- **Keep `NostrMailClient` backwards-compatible** if possible; consumers rely heavily on `send()`, `sync()`, and `watch()`.
- **Add tests** for new storage operations in `nostr_mail_test.dart` or a new feature-specific file.
- **Update `CHANGELOG.md`** with user-visible changes.
- **Update `email-labels.md`** if you change the label protocol.
- **Do not commit `.qwen/` or `pubspec.lock`** (both are gitignored).
- If you introduce a new event kind, add it to `lib/src/constants.dart` and re-export from `lib/nostr_mail.dart` only if it is public API.
