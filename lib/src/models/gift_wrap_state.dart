import 'package:ndk/ndk.dart' show Nip01Event;

/// How far a gift wrap got through processing.
///
/// The stage is what makes a failure resumable: a wrap that reached
/// [unsealed] has already cost its signer approvals, and a later attempt
/// resumes at the Blossom fetch instead of asking for them again.
enum GiftWrapStage {
  /// Stored raw, never opened.
  saved,

  /// Seal and rumor are decrypted and persisted; the email is not built yet.
  unsealed,

  /// Fully processed into the email store. Terminal.
  stored,
}

/// Why the last attempt stopped, and whether trying again can help.
enum GiftWrapFailure {
  /// Nothing will change: the payload cannot be opened with this account's
  /// key, or what it carries is malformed.
  permanent,

  /// A relay, a Blossom server or the network was unavailable.
  transient,

  /// A remote signer answered with an error. NIP-46 carries no error
  /// taxonomy, so a refusal and an impossible decryption look identical;
  /// only a bounded number of attempts tells them apart.
  signer,
}

/// Where a gift wrap stands: how far it got, and what stopped it.
class GiftWrapProgress {
  final GiftWrapStage stage;
  final GiftWrapFailure? failure;
  final int attempts;

  const GiftWrapProgress({
    required this.stage,
    this.failure,
    this.attempts = 0,
  });
}

/// A gift wrap that has not reached the email store, and what stopped it.
class FailedGiftWrap {
  final Nip01Event event;
  final GiftWrapProgress progress;

  const FailedGiftWrap({required this.event, required this.progress});
}
