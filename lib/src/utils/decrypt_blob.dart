import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// Decrypts data using AES-256-GCM
/// [encryptedBytes] - the encrypted data (ciphertext + MAC)
/// [key] - base64 encoded encryption key
/// [nonce] - base64 encoded nonce (salt)
Future<Uint8List> decryptBlob({
  required Uint8List encryptedBytes,
  required String key,
  required String nonce,
}) async {
  final algorithm = AesGcm.with256bits();

  // Decode base64 key and nonce
  final keyBytes = base64Decode(key);
  final nonceBytes = base64Decode(nonce);

  // Extract ciphertext and MAC (MAC is last 16 bytes)
  final macLength = algorithm.macAlgorithm.macLength;
  final ciphertext = encryptedBytes.sublist(
    0,
    encryptedBytes.length - macLength,
  );
  final macBytes = encryptedBytes.sublist(encryptedBytes.length - macLength);

  // Create secret key from bytes
  final secretKey = SecretKey(keyBytes);

  // Create secret box with ciphertext, nonce, and MAC
  final secretBox = SecretBox(
    ciphertext,
    nonce: nonceBytes,
    mac: Mac(macBytes),
  );

  // Decrypt the data
  final decryptedData = await algorithm.decrypt(
    secretBox,
    secretKey: secretKey,
  );

  return Uint8List.fromList(decryptedData);
}
