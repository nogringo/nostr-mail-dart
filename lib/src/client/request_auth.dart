import 'package:ndk/ndk.dart';

/// The identity a request scoped to [pubkey] may be attributed to on relays
/// (NIP-42).
///
/// The account is read from [pubkey] rather than from whoever is logged in:
/// left to ndk the identity is settled when the challenge lands, and by then
/// the account may have changed, so one account's filters would go out under
/// another's.
///
/// [fromStart] sends on a connection bound to the account instead of the
/// anonymous one, so the request is never refused for lack of an identity. It
/// costs a second socket per relay of the set, and answers the challenge of
/// any relay that sends one, including relays that would have served it
/// anonymously.
///
/// An account that cannot sign gets [RelayAuth.never]: it has no answer to a
/// challenge, and saying nothing to ndk would authenticate as the logged
/// account instead.
RelayAuth authFor(Ndk ndk, String pubkey, {bool fromStart = false}) {
  final account = ndk.accounts.accounts[pubkey];
  if (account == null || !account.signer.canSign()) {
    return const RelayAuth.never();
  }
  return fromStart ? RelayAuth.require(account) : RelayAuth.allow(account);
}
