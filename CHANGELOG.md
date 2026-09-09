## Unreleased

- The sync engine authenticates (NIP-42). `wss://auth.nostr1.com` is the first
  default DM relay and refuses an anonymous request, so gift wraps were being
  asked for on a connection that never got to serve them, and the refusal read
  as a relay with nothing to give. Each request now names the active account
  and goes out authenticated from the first page. The identity is part of the
  request, so every account walks its window once more on this upgrade: nothing
  is lost, and no signer approval is spent replaying what the cache already
  holds. A pubkey-only login stops syncing, since it cannot answer a challenge
  and could not decrypt a wrap either. Requires `sync_engine_shim_for_ndk`
  0.6.0, where a request naming nobody no longer authenticates as whoever is
  logged in.
- `getSummaries()` lists a mailbox without reading or parsing any MIME. The
  list methods return `Email`, which holds the whole message body, so drawing
  a screenful of rows pulled every body off disk to show a subject and a
  sender. An `EmailSummary` reads only the indexed columns a row draws:
  sender, recipients, subject, a preview SQLite truncates itself, date,
  folder, read and starred state, labels and attachment metadata. A row costs
  a few hundred bytes instead of the whole message. It returns a
  `PaginatedResult`, now exported, whose `total` and `hasMore` tell an endless
  list when to stop asking.
- `labels` is indexed on `(email_id, recipient_pubkey, label)`. The
  `email_states` view resolves the folder, read and starred state of a row
  through correlated subqueries keyed on `email_id`, and the only index on the
  table started at `recipient_pubkey`, so every one of those subqueries
  rescanned every label of the account. Any query filtering on a folder walked
  the whole mailbox: on a store of 5000 emails and 2500 labels, counting the
  inbox took 360 ms and `getUnreadCount(folder: 'inbox')`, which
  `watchUnreadCount` re-runs on every change, took the same. Both now take
  about 2 ms.
- An `Email` parses its MIME on first read of `.mime` rather than in its
  constructor. Parsing walks the entire part tree and copies every body out of
  `lightMimeText`, and every caller paid for it, including those that only
  wanted an id or a date.
- The store indexes the recipients and the sender's display name. `To`, `Cc`
  and `Bcc` lived only inside the stored MIME, and `from_address` dropped the
  personal name, so no listing could show either without parsing the message.
  Schema version 2: the tables are rebuilt from the NDK cache on first open,
  without network and without a signer.
- A schema change no longer drops the NIP-44 decryptions. What a gift wrap
  yields once opened moves to its own `unsealed` table, kept across the drop
  along with the decrypted settings, so rebuilding the tables costs no signer
  approval. Everything else stays a projection of the NDK cache and of those
  two tables. A wipe the user asks for still takes all of it.
- The client asks for the full replay that refills a dropped projection.
  Nothing else would: the sync engine's coverage does not move across a schema
  change, so its rounds bring no page, and the mailbox stayed empty until a
  `fetchRecent()`.
- Live subscriptions write what they receive to the NDK cache. They wrote
  nothing before (`subscription()` defaults to `cacheWrite: false`), so an
  event seen only in real time was projected and then lost: a rebuild of the
  tables replayed the cache without it, until the sync engine walked its
  period again. The reposts, settings and metadata subscriptions, which
  process nothing themselves, now serve their purpose.

## 3.0.0

- **Breaking**: the mail store moves from sembast to drift (SQLite).
  `NostrMailClient.create` takes a `database: NostrMailDatabase`, which the
  caller opens (`NativeDatabase` on native, `WasmDatabase.open` on web) and
  closes after `dispose()`. The sembast `db` is still required: the broadcast
  queue, the Blossom upload queue, the event scheduler and the sync engine
  keep theirs. Sembast holds every store in memory, which is what made a large
  mailbox cost a gigabyte in a browser tab.
- **Breaking**: `kSchemaVersion` and `migrateSchemaIfNeeded` are gone. A
  schema change bumps `NostrMailDatabase.schemaVersion`, and any mismatch
  drops and rebuilds the tables from the NDK cache when the store opens.
- **Breaking**: `search()` runs on an FTS5 index. It matches words and
  prefixes, case and accent insensitive, instead of arbitrary substrings.
- The stores earlier versions kept in the sembast database are dropped on the
  first `create()`. Nothing is lost: they were a projection of the NDK cache,
  and the next pass rebuilds them without network.
- An email's folder, read and starred state are derived from its labels by a
  SQL view instead of being copied onto the row. A label landing before its
  email, or a wrap coming back through the sync, can no longer leave a row
  out of step with its labels.
- On the web, ship `sqlite3.wasm` and `drift_worker.js` in `web/`; see the
  README.
- **Breaking**: `NostrMailClient.create` takes a `syncEngine`
  (`sync_engine_shim_for_ndk`), which replaces NDK's broken `fetchedRanges`. It
  belongs to the caller: `create()` starts it but never stops nor disposes it.
- **Breaking**: `sync()` and `resync()` are gone. `fetchRecent()` is the only
  one left, and it is the pull-to-refresh gesture. Nothing has to be called to
  stay up to date: the client declares what the active account needs and
  follows logins and account switches, and the engine revisits on its own.
- **Breaking**: `migrateSchemaIfNeeded` no longer takes an `ndk`.
- **Breaking**: `getFailedEvents()` becomes `getFailedGiftWraps()` and returns
  `FailedGiftWrap`, which carries the stage a wrap reached, what stopped it and
  how many attempts it cost.
- **Breaking**: requires `ndk` 0.9.0, `nostr_event_scheduler` 0.4.0,
  `broadcast_queue_shim_for_ndk` 0.5.0, `blossom_upload_queue_shim_for_ndk`
  0.7.0 and `sync_engine_shim_for_ndk` 0.4.0.
- The NDK cache is now the source of truth for raw events, and the local stores
  a projection of it replayed on every page that lands. Mail therefore surfaces
  during a long backfill instead of after it, an event whose processing fails
  is retried on the next pass unless its recorded failure says another attempt
  cannot help, and a schema bump rebuilds the stores without going back to the
  relays.
- `clearLocalAccountData(pubkey:)` and `clearAllLocalData()` no longer touch NDK
  state, so clear the NDK cache too to forget an account entirely.
- **Fix**: a sent email no longer loses its labels when its own gift wrap comes
  back through the sync and rebuilds the row from scratch.
- **Fix**: an email whose labels landed before it now picks them up. The labels
  were saved but had no row to be denormalized onto, so the email stayed in the
  inbox, unread and unstarred, while `getLabels()` reported it trashed, read or
  starred.
- **Fix**: deleting an encrypted email now names its gift wrap in the NIP-09
  request. Only the rumor id was named, an event no relay has ever held, so the
  wrap stayed on the relays forever. NIP-59 has relays honor a deletion signed
  by the pubkey in the wrap's `p` tag, which is the recipient. The rumor id is
  still named too: it is what other devices match against their own rows.
- Gift wraps are also tombstoned by their own event id now, so a relay
  re-serving a deleted one costs a lookup per replay instead of unwrapping and
  unsealing it every time.
- A gift wrap now records why it failed, and that decides what happens next: a
  permanent failure (a local key that cannot open it, a malformed body) is
  never retried, a transient one (relay, Blossom server, network) is retried on
  the next pass, and a remote signer's error is retried `maxSignerAttempts`
  times before the wrap is parked. NIP-46 carries no error taxonomy, so a user
  refusing and a bunker unable to decrypt cannot be told apart, and each
  attempt can cost the user an approval prompt.
- **Fix**: a remote signer's error no longer marks a gift wrap as processed,
  which used to drop the mail for good.
- **Fix**: a gift wrap that arrived while another account was active is
  processed when that account comes back, instead of waiting for an explicit
  `retry`.
- A gift wrap records its seal and rumor as soon as it yields them, so a
  failure on the Blossom body resumes at the download instead of asking the
  signer to decrypt again.
- `getFailedCount()` leaves out permanently failed wraps: anyone can address a
  malformed wrap to an account, so a count a stranger inflates is not worth
  showing. `getFailedGiftWraps()` still lists them.

## 2.6.2

- Every event the SDK enqueues is now attributed to the sending account in the
  broadcast queue, and every blob upload to the uploading account. Gift wraps
  are attributed to the sender rather than to their ephemeral event pubkey, so
  they can be filtered and cleared per account.
- Blob uploads are now signed by the account that queued them instead of by
  whoever is logged in when a retry fires.
- `clearLocalAccountData(pubkey:)` and `clearAllLocalData()` now also drop the
  matching entries in the broadcast and Blossom upload queues, so nothing keeps
  being retried for an account that logged out. Only queues the client created
  itself are touched: one passed to `create()` may be shared with other SDKs,
  so clearing it stays the caller's job.
- Entries queued by an earlier version carry no account label. They keep being
  retried and are only removed by `clearAllLocalData()`.

## 2.6.1

- Upgrade `nostr_event_scheduler` to 0.3.0 (multi-account, multi-DVM API) and
  adapt the internal `ScheduleManager`: every scheduler call now acts for the
  active account explicitly. No public API change.
- Bump `broadcast_queue_shim_for_ndk` to 0.4.0, `blossom_cache` to 0.4.0 and
  `blossom_upload_queue_shim_for_ndk` to 0.6.0.

## 2.6.0

- **New**: `clearLocalAccountData(pubkey:)` removes local cache for one
  account, and `clearAllLocalData()` removes local cache for every account.
  Both clear matching NDK fetched ranges so the next sync can rebuild from
  relays. `clearAll()` stays as an alias of `clearAllLocalData()`.
- **Fix**: Gift wraps are now stored with their own `recipientPubkey` and read
  back per account, so `getGiftWrap()`, `getSeal()`, `getRumor()`, retries, the
  failed-event counters and deletions never touch another account's cache. A
  wrap that arrives mid account-switch is kept for its own recipient instead of
  being dropped once its fetched range is marked covered.
- **Breaking**: Bumped local schema version to rebuild gift-wrap records with
  `recipientPubkey`, allowing account-scoped local data cleanup. Existing local
  caches are wiped once on startup and rebuilt from the relays.

## 2.5.0

- **New**: `openEmail()` opens an email from a Nostr event reference, accepting
  either a public email event id (kind 1301) or an outer NIP-59 gift wrap id
  (kind 1059), with optional relay hints for notification/deep-link flows.

## 2.4.0

- **New**: `sendMime()` accepts an optional `beforePublish` callback, invoked
  with each fully built outgoing event and its resolved destination relays
  immediately before it is added to the broadcast queue.

## 2.3.0

- **New**: Email scheduling through a Scheduler DVM. `scheduleEmail()`/`scheduleMime()` queue an email for future delivery at a given time (one DVM job per outgoing gift wrap or public event); `getScheduledEmails()`/`watchScheduledEmails()` list and observe them; `cancelScheduledEmail()` deletes the package so the DVM never sends; `getScheduledMime()` reconstructs the full editable MIME to re-open a scheduled email in a composer; `resyncScheduledEmails()` forces a one-shot resync; `startScheduling()`/`stopScheduling()` toggle live DVM feedback and multi-device sync. Configure the DVM via `schedulerDvm`/`schedulerDvmReadRelays` on `create()`.
- **New**: Exported `ScheduledEmail` and `ScheduledEmailStatus`.
- **New**: A scheduled email dates its rumors and MIME `Date` header at the schedule time, so the recipient sees the send date; the visible gift-wrap envelope stays randomized in the 2 days before it, never revealing that the email was pre-built.
- **Refactor**: Split event building from broadcasting in `EmailSender` behind a `Delivery` abstraction, so immediate and scheduled sends share one build path.
- **Dependencies**: Added `nostr_event_scheduler ^0.2.3`. Upgraded `ndk` from `0.8.4-dev.5` to `0.8.4-dev.7`.

## 2.2.2

- **Breaking**: `send()`/`sendMime()` take typed `Recipient` lists (`NostrRecipient`/`SmtpRecipient`) per `to`/`cc`/`bcc` instead of `MailAddress`; the caller picks each recipient's transport. `resolveRecipient()` returns a `Recipient` (not a pubkey), drops its `from` arg, and throws on a NIP-05 network/malformed result instead of misrouting a Nostr recipient to the bridge. `Recipient` types and `resolveRecipient()` are now exported.
- **New**: Emails to legacy recipients carry the SMTP envelope on the bridge rumor (`mail-from` + one `rcpt-to` per `to`/`cc`/`bcc`), fixing BCC-to-legacy delivery; bridge delivery now applies to public emails too.
- **Breaking**: Raised the minimum Dart SDK version from 3.10.8 to 3.12.0.
- **Dependencies**: Upgraded `ndk` from `0.8.4-dev.2` to `0.8.4-dev.5` for improved broadcast authentication and live subscription handling.
- **Refactor**: Simplified internal `NostrMailClient`, `SyncEngine`, and `BridgeResolver` constructors using Dart 3.12 private named initializing formals.
- **Tests**: Updated `MockRelay` to broadcast matching events to live subscriptions and apply NIP-01 replacement rules to replaceable and addressable events.
- **Tests**: Added remote-signer hooks for validating signer-modified event timestamps and content, with safer dynamic tag parsing.
- **Tests**: Removed the obsolete `mark_unread_persists` integration test after the mock relay began honoring deletion requests, which meant the test no longer exercised stale label re-delivery.

## 2.2.1

- **Fix**: NIP-05 recipient resolution now uses `ndk.nip05.resolve()` from NDK `0.8.4-dev.2`, reusing NDK's cache and in-flight request deduplication.

## 2.2.0

- **Breaking**: `NostrMailClient.delete(...)` now accepts `Iterable<String>` and publishes one batched NIP-09 deletion request with multiple `e` tags, including any NIP-32 label events attached to those emails.
- **Fix**: Local email deletions now create tombstones immediately, so stale relays that ignore NIP-09 cannot re-serve deleted emails into the local cache on the next sync.
- **Fix**: Deleting an email now removes the associated gift-wrap cache entry by decrypted rumor id instead of assuming the gift-wrap event id equals the email id.
- **Fix**: Restoring a trashed sent email now returns it to Sent instead of Inbox by deriving the restored mailbox from the sender/owner pubkeys.

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
