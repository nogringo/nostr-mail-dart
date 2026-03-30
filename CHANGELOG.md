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
