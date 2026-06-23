import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/shared/nips/nip19/nip19.dart';

/// A send recipient whose transport - native Nostr or SMTP bridge - is decided
/// by the caller. Passing recipients explicitly means the send path never has
/// to guess from a NIP-05 lookup, so a transient lookup failure can no longer
/// misroute a Nostr recipient to the bridge.
sealed class Recipient {
  /// Address used in the MIME headers: the display address a recipient sees and
  /// the envelope a bridge relays on.
  MailAddress get mailAddress;
}

/// A native Nostr recipient, addressed by its hex [pubkey].
class NostrRecipient extends Recipient {
  NostrRecipient({required this.pubkey, required this.mailAddress});

  /// Build from a pubkey alone, deriving `<npub>@nostr` as the display address.
  NostrRecipient.fromPubkey(this.pubkey)
    : mailAddress = MailAddress(null, '${Nip19.encodePubKey(pubkey)}@nostr');

  final String pubkey;

  @override
  final MailAddress mailAddress;
}

/// A legacy email recipient, relayed through the sender's SMTP bridge.
class SmtpRecipient extends Recipient {
  SmtpRecipient(String email) : mailAddress = MailAddress(null, email);

  SmtpRecipient.fromMailAddress(this.mailAddress);

  @override
  final MailAddress mailAddress;

  String get email => mailAddress.email;
}
