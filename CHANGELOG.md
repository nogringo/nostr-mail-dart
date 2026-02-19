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
