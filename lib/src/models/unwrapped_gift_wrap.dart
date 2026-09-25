import 'package:ndk/ndk.dart';

class UnwrappedGiftWrap {
  /// Null when the wrap carried a signed event directly, as a label does.
  final Nip01Event? seal;

  /// What the wrap delivered: the rumor inside the seal for an email, the
  /// signed event itself for a label.
  final Nip01Event payload;

  UnwrappedGiftWrap({this.seal, required this.payload});
}
