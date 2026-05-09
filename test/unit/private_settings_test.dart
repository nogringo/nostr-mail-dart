import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

void main() {
  group('PrivateSettings model', () {
    test('fromJson parses all fields', () {
      final json = jsonEncode({
        'signature': 'Sent via Nostr',
        'bridges': ['nostr.mail', 'bridge.example.com'],
        'identities': [
          'Alice Real <npub1abc@test.mail>',
          'npub1def@bridge.com',
        ],
      });

      final settings = PrivateSettings.fromJson(json);

      expect(settings.defaultAddress, isNotNull);
      expect(settings.defaultAddress!.personalName, 'Alice Real');
      expect(settings.defaultAddress!.email, 'npub1abc@test.mail');
      expect(settings.signature, 'Sent via Nostr');
      expect(settings.bridges, ['nostr.mail', 'bridge.example.com']);
      expect(settings.identities, isNotNull);
      expect(settings.identities!.length, 2);
      expect(settings.identities![0].personalName, 'Alice Real');
    });

    test('fromJson handles empty/null fields', () {
      final settings = PrivateSettings.fromJson('{}');

      expect(settings.defaultAddress, isNull);
      expect(settings.signature, isNull);
      expect(settings.bridges, isNull);
      expect(settings.identities, isNull);
    });

    test('fromJson handles partial fields', () {
      final json = jsonEncode({'signature': 'Custom signature'});

      final settings = PrivateSettings.fromJson(json);

      expect(settings.defaultAddress, isNull);
      expect(settings.signature, 'Custom signature');
      expect(settings.bridges, isNull);
      expect(settings.identities, isNull);
    });

    test('toJson serializes all fields', () {
      final settings = PrivateSettings(
        signature: 'Sent via Nostr',
        bridges: ['nostr.mail'],
        identities: [
          MailAddress('Alice', 'alice@nostr.mail'),
          MailAddress(null, 'bob@bridge.com'),
        ],
      );

      final json = jsonDecode(settings.toJson()) as Map<String, dynamic>;

      expect(json['signature'], 'Sent via Nostr');
      expect(json['bridges'], ['nostr.mail']);
      expect(json.containsKey('default_address'), isFalse);
      expect(json['identities'], isNotNull);
      expect((json['identities'] as List).length, 2);
    });

    test('toJson omits null fields', () {
      final settings = const PrivateSettings(signature: 'Only signature');

      final json = jsonDecode(settings.toJson()) as Map<String, dynamic>;

      expect(json['signature'], 'Only signature');
      expect(json.containsKey('bridges'), isFalse);
      expect(json.containsKey('identities'), isFalse);
    });

    test('roundtrip preserves data', () {
      final original = PrivateSettings(
        signature: 'My signature',
        bridges: ['a.com', 'b.com'],
        identities: [
          MailAddress('Alice', 'alice@nostr.mail'),
          MailAddress(null, 'bob@bridge.com'),
        ],
      );

      final restored = PrivateSettings.fromJson(original.toJson());

      expect(restored.signature, original.signature);
      expect(restored.bridges, original.bridges);
      expect(
        restored.defaultAddress!.encode(),
        original.defaultAddress!.encode(),
      );
      expect(restored.identities, isNotNull);
      expect(restored.identities!.length, 2);
      expect(restored.identities![0].personalName, 'Alice');
      expect(restored.identities![1].personalName, isNull);
    });

    test('copyWith updates fields', () {
      final original = PrivateSettings(
        signature: 'Old signature',
        bridges: ['old.com'],
      );

      final updated = original.copyWith(signature: 'New signature');

      expect(updated.signature, 'New signature');
      expect(updated.bridges, ['old.com']); // unchanged
      expect(updated.sourceEvent, isNull); // cleared by copyWith
    });

    test('copyWith clears fields', () {
      final original = PrivateSettings(
        signature: 'signature',
        bridges: ['bridge.com'],
        identities: [MailAddress('Alice', 'alice@test.com')],
      );

      final updated = original.copyWith(
        clearSignature: true,
        clearBridges: true,
        clearIdentities: true,
      );

      expect(updated.defaultAddress, isNull);
      expect(updated.signature, isNull);
      expect(updated.bridges, isNull);
      expect(updated.identities, isNull);
    });

    test('copyWith updates identities', () {
      final original = PrivateSettings(
        identities: [MailAddress('Old', 'old@test.com')],
      );

      final updated = original.copyWith(
        identities: [MailAddress('New', 'new@test.com')],
      );

      expect(updated.identities, isNotNull);
      expect(updated.identities!.length, 1);
      expect(updated.identities![0].personalName, 'New');
    });

    test('copyWith clears sourceEvent', () {
      final settings = PrivateSettings(signature: 'test', sourceEvent: null);
      final updated = settings.copyWith(signature: 'updated');
      expect(updated.sourceEvent, isNull);
    });

    test('toString is descriptive', () {
      final settings = PrivateSettings(
        signature: 'test-sig',
        bridges: ['a.com'],
      );

      expect(settings.toString(), contains('test-sig'));
      expect(settings.toString(), contains('a.com'));
    });
  });
}
