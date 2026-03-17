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

/// Label namespace for mail-related labels
const labelNamespace = 'mail';

/// Maximum size for inline MIME content (60KB)
/// Larger emails are stored on Blossom servers
const maxInlineSize = 60000;

/// Default DM relays used when user has no relay list configured
const defaultDmRelays = [
  'wss://auth.nostr1.com',
  'wss://nostr-01.uid.ovh',
  'wss://nostr-02.uid.ovh',
];

/// Default Blossom servers used when user has no server list configured
const defaultBlossomServers = [
  'https://blossom.yakihonne.com',
  'https://blossom-01.uid.ovh',
  'https://blossom-02.uid.ovh',
  'https://blossom.primal.net',
];
