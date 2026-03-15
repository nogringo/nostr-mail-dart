import 'dart:convert';
import 'dart:typed_data';

import 'package:nostr_mail/src/utils/decrypt_blob.dart';
import 'package:nostr_mail/src/utils/encrypt_blob.dart';
import 'package:test/test.dart';

void main() {
  group('Encrypt/Decrypt Roundtrip Tests', () {
    test('should encrypt and decrypt small text data', () async {
      // Arrange
      final originalData = Uint8List.fromList('Hello, World!'.codeUnits);

      // Act
      final encryptedBlob = await encryptBlob(originalData);
      final decryptedData = await decryptBlob(
        encryptedBytes: encryptedBlob.bytes,
        key: encryptedBlob.key,
        nonce: encryptedBlob.nonce,
      );

      // Assert
      expect(decryptedData, equals(originalData));
      expect(String.fromCharCodes(decryptedData), equals('Hello, World!'));
    });

    test('should encrypt and decrypt binary data (image-like)', () async {
      // Arrange - create some binary data that looks like a small image
      final originalData = Uint8List.fromList(
        List.generate(1024, (i) => i % 256),
      );

      // Act
      final encryptedBlob = await encryptBlob(originalData);
      final decryptedData = await decryptBlob(
        encryptedBytes: encryptedBlob.bytes,
        key: encryptedBlob.key,
        nonce: encryptedBlob.nonce,
      );

      // Assert
      expect(decryptedData, equals(originalData));
      expect(decryptedData.length, equals(1024));
    });

    test('should encrypt and decrypt empty data', () async {
      // Arrange
      final originalData = Uint8List(0);

      // Act
      final encryptedBlob = await encryptBlob(originalData);
      final decryptedData = await decryptBlob(
        encryptedBytes: encryptedBlob.bytes,
        key: encryptedBlob.key,
        nonce: encryptedBlob.nonce,
      );

      // Assert
      expect(decryptedData, equals(originalData));
      expect(decryptedData.isEmpty, isTrue);
    });

    test('should encrypt and decrypt large data', () async {
      // Arrange - 1MB of random data
      final originalData = Uint8List.fromList(
        List.generate(1024 * 1024, (i) => i % 256),
      );

      // Act
      final encryptedBlob = await encryptBlob(originalData);
      final decryptedData = await decryptBlob(
        encryptedBytes: encryptedBlob.bytes,
        key: encryptedBlob.key,
        nonce: encryptedBlob.nonce,
      );

      // Assert
      expect(decryptedData, equals(originalData));
      expect(decryptedData.length, equals(1024 * 1024));
    });

    test('should produce different ciphertext for same plaintext', () async {
      // Arrange
      final originalData = Uint8List.fromList('Test data'.codeUnits);

      // Act - encrypt twice
      final encryptedBlob1 = await encryptBlob(originalData);
      final encryptedBlob2 = await encryptBlob(originalData);

      // Assert - ciphertext should be different due to random key/nonce
      expect(encryptedBlob1.bytes, isNot(equals(encryptedBlob2.bytes)));
      expect(encryptedBlob1.key, isNot(equals(encryptedBlob2.key)));
      expect(encryptedBlob1.nonce, isNot(equals(encryptedBlob2.nonce)));

      // But both should decrypt to the same plaintext
      final decrypted1 = await decryptBlob(
        encryptedBytes: encryptedBlob1.bytes,
        key: encryptedBlob1.key,
        nonce: encryptedBlob1.nonce,
      );
      final decrypted2 = await decryptBlob(
        encryptedBytes: encryptedBlob2.bytes,
        key: encryptedBlob2.key,
        nonce: encryptedBlob2.nonce,
      );
      expect(decrypted1, equals(decrypted2));
    });

    test('should fail decryption with wrong key', () async {
      // Arrange
      final originalData = Uint8List.fromList('Secret message'.codeUnits);
      final encryptedBlob = await encryptBlob(originalData);

      // Generate a wrong key
      final wrongBlob = await encryptBlob(
        Uint8List.fromList('other'.codeUnits),
      );

      // Act & Assert - should throw exception
      expect(
        () => decryptBlob(
          encryptedBytes: encryptedBlob.bytes,
          key: wrongBlob.key,
          nonce: encryptedBlob.nonce,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('should fail decryption with wrong nonce', () async {
      // Arrange
      final originalData = Uint8List.fromList('Secret message'.codeUnits);
      final encryptedBlob = await encryptBlob(originalData);

      // Generate a wrong nonce
      final wrongBlob = await encryptBlob(
        Uint8List.fromList('other'.codeUnits),
      );

      // Act & Assert - should throw exception
      expect(
        () => decryptBlob(
          encryptedBytes: encryptedBlob.bytes,
          key: encryptedBlob.key,
          nonce: wrongBlob.nonce,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('should fail decryption with tampered ciphertext', () async {
      // Arrange
      final originalData = Uint8List.fromList('Secret message'.codeUnits);
      final encryptedBlob = await encryptBlob(originalData);

      // Tamper with the ciphertext
      final tamperedBytes = Uint8List.fromList(encryptedBlob.bytes);
      if (tamperedBytes.isNotEmpty) {
        tamperedBytes[0] = (tamperedBytes[0] + 1) % 256;
      }

      // Act & Assert - should throw exception due to auth tag mismatch
      expect(
        () => decryptBlob(
          encryptedBytes: tamperedBytes,
          key: encryptedBlob.key,
          nonce: encryptedBlob.nonce,
        ),
        throwsA(isA<Exception>()),
      );
    });

    test('should handle UTF-8 data correctly', () async {
      // Arrange - UTF-8 text with special characters
      const originalText = 'Hello 世界！🌍 Привет!';
      final originalData = utf8.encode(originalText);

      // Act
      final encryptedBlob = await encryptBlob(originalData);
      final decryptedData = await decryptBlob(
        encryptedBytes: encryptedBlob.bytes,
        key: encryptedBlob.key,
        nonce: encryptedBlob.nonce,
      );

      // Assert
      expect(utf8.decode(decryptedData), equals(originalText));
    });
  });
}
