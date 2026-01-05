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
