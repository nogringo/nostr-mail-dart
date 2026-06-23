/// Outcome of resolving a recipient address to a Nostr [pubkey].
///
/// For a legacy recipient [pubkey] is the SMTP bridge and [legacyAddress]
/// holds the email address the bridge needs for its `rcpt-to` envelope tag.
class ResolvedRecipient {
  const ResolvedRecipient({required this.pubkey, this.legacyAddress});

  final String pubkey;
  final String? legacyAddress;

  bool get isBridge => legacyAddress != null;
}
