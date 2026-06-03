## 2.2.0

- **Breaking**: `NostrMailClient.delete(...)` now accepts `Iterable<String>` and publishes one batched NIP-09 deletion request with multiple `e` tags, including any NIP-32 label events attached to those emails.
- **Fix**: Local email deletions now create tombstones immediately, so stale relays that ignore NIP-09 cannot re-serve deleted emails into the local cache on the next sync.
- **Fix**: Deleting an email now removes the associated gift-wrap cache entry by decrypted rumor id instead of assuming the gift-wrap event id equals the email id.

## 2.1.0

- **Breaking**: `getPrivateSettings()` is now local-first. It reads the decrypted local settings cache without fetching from relays or requiring a signer.
- **Breaking**: Removed `getCachedPrivateSettings()`. Use `getPrivateSettings()` for the async local read or `cachedPrivateSettings` for the synchronous in-memory getter.
- **New**: `fetchPrivateSettings()` fetches NIP-78 settings from relays, decrypts them, and refreshes the local cache.
- **Change**: `updatePrivateSettings()` now reads existing settings through the local-first `getPrivateSettings()` path, then reuses `setPrivateSettings()` to encrypt and enqueue relay sync.
- **Fix**: `NostrMailClient.create()` now primes `cachedPrivateSettings` from local storage when a pubkey is configured. Previously the sync getter stayed `null` until a caller awaited a settings read, which made user-facing settings (signature, bridges, identities) appear reset after sign-out/sign-in: auth-state listeners fired before the new client was constructed, and nothing re-triggered the load once it was.

## 2.0.1

- **Fix**: Marking an email as unread no longer reverts to read after a refresh. A NIP-09 deletion tombstone store records every deleted label event id and `onLabelAddition` skips any event that has been tombstoned, so a stale label event re-served by a relay that does not honor NIP-09 (or by NDK's in-memory cache, which never acts on deletions) is dropped instead of re-applied. Works the same way for star/unstar and folder restores.
- **Breaking**: `Email.isBridged` is now a `final` field instead of a getter. The previous getter parsed the MIME `From:` header heuristically; per the nostr-mail-core spec, bridge detection must come from the `mail-from` tag on the rumor. The parser (`parseEmailEvent`) and `EmailSender._saveSelfCopy` now derive the value from `event.getFirstTag('mail-from') != null`, and `EmailRecord.toEmail()` round-trips it through storage. Callers that construct `Email` directly must now pass `isBridged:`.
- **Fix**: Inbound nostr-native emails whose sender did not set a MIME `From:` header are no longer falsely classified as bridged. The old heuristic returned `true` whenever the From address was missing or unparseable; the spec-compliant tag check makes the classification deterministic.

## 2.0.0

- **Breaking**: Attachments no longer live in Sembast. Each attachment is extracted at sync time and stored in `BlossomCache` keyed by its content sha256 (unpinned, LRU-evictable). The original encrypted Blossom blob remains pinned as the source of truth, so any evicted attachment can be regenerated locally without going back to the relays.
- **Breaking**: `Email` no longer exposes `rawContent`. It now carries `lightMimeText` (the RFC 2822 envelope with attachment bodies emptied) and `attachmentRefs` (`{ filename, contentType, size, sha256, contentId }`). The `email.mime` getter still returns a parsed `MimeMessage`, but its attachment parts have empty bodies.
- **Breaking**: `EmailRecord` mirrors the same shape change. Existing rows are wiped on upgrade via the `kSchemaVersion` bump (full resync from relays + Blossom servers).
- **Breaking**: `EmailParser.parseMime` is removed. Construct `Email` directly, or use `MimeMessage.parseFromText` if all you need is a parsed MIME.
- **Breaking**: `parseEmailEvent` and `SyncEngine` now require a non-null `BlossomCache`.
- **New**: `NostrMailClient.getAttachmentBytes(email, ref)` - lazy load attachment bytes. Cache hit is instant; cache miss decrypts the source-of-truth blob and re-extracts every attachment, then serves the requested one.
- **New**: `NostrMailClient.getRawMimeText(email)` and `getRawMime(email)` - reconstruct the original byte-exact RFC 2822 MIME on demand (for `.eml` export, reply with full quote, etc.).
- **Fix**: Opening a folder containing emails with large attachments no longer triggers a multi-second MIME parse on every list load (previous behaviour pulled the full base64 attachment off disk for every row, just to display the list).

## 1.16.0

- **New**: Durable outbound queues - `OfflineBroadcast` for Nostr events and `OfflineBlossomUpload` for blob uploads. Both are exposed on `NostrMailClient` (`broadcastQueue`, `blossomUploadQueue`).
- **New**: Local-first `send()` / `sendMime()` / `delete()` - persisted locally before any network attempt; enqueued for automatic retry until fully delivered.
- **New**: `filters.dart` - single source of truth for all 7 Nostr query filters. Eliminates duplication between `SyncEngine` and `WatchManager`.
- **Improvement**: `SyncEngine` now syncs all filters defined in `filters.md` (gift wraps, public emails, labels, reposts, settings, metadata/relay lists). Label and deletion filters are now more precise (`#L: mail`, unified `#k` tag).
- **Improvement**: Parallelized `fetchRecent()` - fetches all 7 filter categories concurrently, then processes events in parallel via `GapSync.processBatch()` and `Future.wait`. Leverages NDK PR #632 signer concurrency queue to protect remote signers.
- **Improvement**: Downloaded Blossom blobs are now cached locally. Subsequent reparses (e.g. after schema migration) reuse the cached encrypted blob instead of re-downloading.

## 1.15.0

- **New**: Automatic schema migration on client construction
  - Local stores (`emails`, `labels`, `gift_wraps`, `private_settings`) and ndk fetched ranges are wiped and rebuilt on every schema version mismatch — the client re-syncs from relays and Blossom on next sync.
  - `kSchemaVersion` constant: bump it whenever the shape of any locally stored record changes.
  - `migrateSchemaIfNeeded(db:, ndk:)` exposed for advanced cases (manual force-resync, tests). Returns `true` when a migration ran.
- **API change**: `NostrMailClient(...)` → `await NostrMailClient.create(...)`
  - The factory is now async so the migration runs before any repository touches the DB. Update call sites accordingly.

## 1.14.2

- **Fix**: Removed manual MIME header unfolding - delegate to `enough_mail_plus` which correctly handles RFC 2822 folding

## 1.14.1

- **Improvement**: split client.dart in multiple files

## 1.14.0

- **New**: NIP-18 repost support
  - `repost(Nip01Event emailEvent)` — Repost an email to followers using kind 16 generic repost

## 1.13.0

- **New**: Added `getTrashedEmailsOlderThan` method to easily query old deleted emails.
- **Improvement**: `saveLabel` now properly stores the original Nostr event's `createdAt` timestamp, allowing duration-based queries on labels.
- **Fix**: Resolved state bleeding in tests by ensuring isolated in-memory database filenames for Sembast.

## 1.12.1

- **Fix**: BCC visibility rules now properly applied for email privacy
  - `removeBccHeaders()` — Utility function that removes `Bcc` and `Resent-Bcc` headers from MIME messages
  - `sendMime()` now correctly applies BCC visibility rules:
    - **Sender's copy** (keepCopy): sees TO + CC + BCC (all recipients visible)
    - **TO/CC recipients**: sees TO + CC only (BCC hidden)
    - **BCC recipients**: sees TO + CC only (other BCC hidden for privacy)
  - BCC recipients are now hidden from TO/CC recipients per email standards

## 1.12.0

- **New**: Access to technical NIP-59 details (Gift Wrap, Seal, Rumor)
  - `getGiftWrap(emailId)` — Retrieve the original kind 1059 event
  - `getSeal(emailId)` — Retrieve the decrypted kind 13 seal event
  - `getRumor(emailId)` — Retrieve the decrypted kind 1301 rumor event
- **Improvement**: Enhanced Gift Wrap storage
  - `GiftWrapStore` now persists decrypted seals and rumors
  - Faster retrieval of technical details without re-decryption
- **New**: `UnwrappedGiftWrap` model for handling NIP-59 event pairs

## 1.11.0

- **New**: `identities` field in `PrivateSettings` — a list of RFC 5322 `MailAddress` entries for multi-identity support
  - `identities` replaces the single `defaultAddress` concept with a flexible list
  - `defaultAddress` is now a convenience getter returning `identities?.first`
  - `updatePrivateSettings()` accepts `identities` and `clearIdentities` parameters
  - `send()` now uses the first identity as the default "From" address when `from` is not provided
- **Breaking**: `defaultAddress` removed from `PrivateSettings` constructor, `fromJson`, `toJson`, and `copyWith`
- **Breaking**: `updatePrivateSettings()` no longer accepts `defaultAddress` or `clearDefaultAddress` parameters

## 1.10.0

- **New**: NIP-78 private settings with NIP-44 encryption for cross-device synchronization
  - `PrivateSettings` model: `signature`, `defaultAddress`, `bridges`, `sourceEvent`
  - `getPrivateSettings()` — fetch and decrypt from relays (write relays, kind 30078)
  - `setPrivateSettings()` — encrypt and broadcast to relays
  - `updatePrivateSettings()` — update a single field with read-modify-write
  - `getCachedPrivateSettings()` — read local decrypted cache (no signer required)
  - `cachedPrivateSettings` — synchronous getter for in-memory cache (multi-pubkey Map)
  - `PrivateSettingsStore` — local decrypted JSON cache keyed by pubkey
  - Settings cleared on `clearAll()`
  - Comprehensive unit and integration tests

## 1.9.1

- **Fix**: Reduce Blossom threshold from 60KB to 32KB to prevent NIP-44 plaintext limit overflow. NIP-59 double wrapping (Rumor → Seal → Gift Wrap) expands payload size via Base64 + padding, making 60KB unsafe.

## 1.9.0

- **Breaking**: Refactored `Email` model to use `MimeMessage` internally for RFC 2822 compliance
  - Removed direct fields: `from`, `to`, `subject`, `body`, `date`
  - New API: access parsed data via `email.mime.fromEmail`, `email.mime.to`, `email.mime.decodeSubject()`, `email.mime.decodeTextPlainPart()`, `email.mime.decodeTextHtmlPart()`
  - Added `htmlBody` and `textBody` getters for direct access
  - `date` now uses MIME `Date` header with fallback to Nostr event creation time
- **New**: `createdAt` field on `Email` to preserve original Nostr event timestamp
- **New**: `rawMime` getter as alias for `rawContent`
- **Performance**: `EmailReceived` event now contains full `Email` object instead of just `emailId`, `from`, `subject` - eliminates redundant database lookups
- **Performance**: `onEmail` stream no longer calls `getEmail()` for each event
- **Fix**: JSON serialization handles nullable `from` and `subject` fields for malformed emails
- **Fix**: Tests updated to use new MIME-based API throughout

## 1.8.1

- **Fix**: Switch to `enough_mail_plus` to fix critical email header folding issues. This resolves problems where long email addresses in `From` headers were being incorrectly folded, causing SpamAssassin flags and delivery issues.
- **Improvement**: Enhanced RFC-compliance for email rendering.

## 1.8.0

- **New**: Global email search functionality. Search by subject, body, or sender across all local emails using Sembast regex filters. Search is case-insensitive and handles special characters safely.

## 1.7.0

- **New**: Support for large emails (> 60KB) via Blossom storage

## 1.6.1

- **Fix**: Folder labels are now mutually exclusive. When adding a `folder:` label (inbox, sent, trash, archive), any existing `folder:` label is automatically removed. This prevents emails from appearing in multiple folder views simultaneously when moved between folders.

## 1.6.0

- **New**: Support for formatted email addresses with display names (e.g., `"Alice" <alice@uid.ovh>`)
- **New**: `resolveRecipient()` function extracted to `utils/recipient_resolver.dart` for better testability
- **Improvement**: Use `enough_mail`'s `MailAddress.parse()` and `encode()` for RFC-compliant address formatting
- **Fix**: Domain extraction now works correctly when `from` address contains display name

## 1.5.0

- **New**: Archives helper functions

## 1.4.5

- **Fix**: html content is encoded in base64

## 1.4.4

- **Refactor**: improve gift wrap processing and simplify API

## 1.4.3

- **Fix**: save giftwraps events outside of NDK cache

## 1.4.2

- **New**: add fetchRecent() for simple parallel sync without fetchedRanges

## 1.4.0

- **New**: `resync()` method to clear fetchedRanges and sync from scratch (useful for recovering late-arriving events)
- **Improvement**: Refactored filter creation into reusable private methods

## 1.3.1

- **Bug fix**: `recipientPubkey` now correctly extracted from the `p` tag of the email event instead of using the gift wrap recipient
- **Bug fix**: Fallback to HTML body for single-part HTML emails
- **Breaking**: Emails without a `p` tag are now skipped (malformed emails)

## 1.3.0

- **New**: NIP-32 labels system (`addLabel`, `removeLabel`, `moveToTrash`, `markAsRead`, `star`, etc.)
- **New**: Unified `watch()` stream with `MailEvent` sealed class (`EmailReceived`, `EmailDeleted`, `LabelAdded`, `LabelRemoved`)
- **New**: Convenience stream getters (`onEmail`, `onTrash`, `onRead`, `onStarred`, `onLabel`)
- **New**: `getInboxEmails()` and `getSentEmails()` with pagination and `includeTrashed` option
- **New**: `htmlBody` getter on `Email` (parsed on demand from rawContent)
- **New**: `stopWatching()` method to close stream and cleanup resources
- **Improvement**: Local-first labels (save and notify immediately, broadcast in background)
- **Improvement**: Shared broadcast stream for `watch()` (multiple listeners share same subscriptions)

## 1.2.2

- Use the new ndk version

## 1.2.1

- Use the new ndk version

## 1.2.0

- **Performance fix**: `watchInbox()` now uses `limit: 0` to only receive new real-time events, avoiding re-processing of historical gift wraps at startup
- **New**: `sync()` now accepts optional `limit`, `since`, and `until` parameters for incremental sync

## 1.1.1

- **Security fix**: Added `recipientPubkey` field to Email model to properly filter emails by recipient
- **Performance fix**: Mark all gift wraps as processed after decryption to avoid re-decrypting DMs and other non-email content on each sync

## 1.1.0

- RFC 2822 compatibility: addresses without domain now get `@nostr` suffix
- Standardized on npub format for all Nostr addresses (hex pubkeys auto-converted)
- Fixed: "To" field was empty when sending to npub addresses

## 1.0.0

- Initial version.
