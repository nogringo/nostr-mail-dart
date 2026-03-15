import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:nostr_mail/src/models/encrypted_blob.dart';

/// Encrypts data using AES-256-GCM
/// Returns the encrypted blob with key, nonce, and auth tag
Future<EncryptedBlob> encryptBlob(Uint8List bytes) async {
  final algorithm = AesGcm.with256bits();

  // Generate random secret key
  final secretKey = await algorithm.newSecretKey();

  // Encrypt with the key
  final secretBox = await algorithm.encrypt(bytes, secretKey: secretKey);

  // Concatenate ciphertext + MAC for storage
  final macBytes = secretBox.mac.bytes;
  final encryptedData = Uint8List.fromList([
    ...secretBox.cipherText,
    ...macBytes,
  ]);

  return EncryptedBlob(
    bytes: encryptedData,
    key: base64Encode(await secretKey.extractBytes()),
    nonce: base64Encode(secretBox.nonce),
  );
}
