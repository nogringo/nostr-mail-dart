/// Nostr Mail protocol constants.
library;

/// Email event kind (NIP-TBD)
const emailKind = 1301;

/// DM relay list event kind (NIP-17)
const dmRelayListKind = 10050;

/// Deletion request event kind (NIP-09)
const deletionRequestKind = 5;

/// Gift wrap event kind (NIP-59)
const giftWrapKind = 1059;

/// Label event kind (NIP-32)
const labelKind = 1985;

/// Relay list event kind (NIP-65)
const relayListKind = 10002;

/// Text note repost kind (NIP-18)
const textRepostKind = 6;

/// Generic repost kind (NIP-18)
const genericRepostKind = 16;

/// Label namespace for mail-related labels
const labelNamespace = 'mail';

/// Maximum size for inline MIME content (32KB).
/// NIP-44 (used in Gift Wraps) has a strict 65,535-byte plaintext limit.
/// Because NIP-59 uses double wrapping (Rumor → Seal → Gift Wrap),
/// and each encryption step expands the size (Base64 + Padding),
/// a 32KB threshold is safe.
/// Larger emails are stored on Blossom servers.
const maxInlineSize = 32768;

/// Default DM relays used when user has no relay list configured
const recommendedDmRelays = [
  'wss://auth.nostr1.com',
  'wss://nostr-01.uid.ovh',
  'wss://nostr-02.uid.ovh',
];

/// Default Blossom servers used when user has no server list configured
const recommendedBlossomServers = [
  'https://blossom.yakihonne.com',
  'https://blossom-01.uid.ovh',
  'https://blossom-02.uid.ovh',
  'https://blossom.primal.net',
];

/// NIP-78 application-specific data event kind
const appSettingsKind = 30078;

/// D-tag for public settings
const publicSettingsDTag = 'nostr-mail/settings';

/// D-tag for private (encrypted) settings
const privateSettingsDTag = 'nostr-mail/settings/private';
