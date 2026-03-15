import 'dart:typed_data';

class EncryptedBlob {
  final Uint8List bytes;
  final String key;
  final String nonce;

  EncryptedBlob({required this.bytes, required this.key, required this.nonce});
}
