import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

void main() {
  const full = 'a1b2c3d4e5f60718';
  const short = '9e8d7c6b5a493827';
  const pseudo = 'Pseudo <alice@example.com>';
  const bridged = '<npub1abc@bridge.com>';

  PrivateSettings settings(Map<String, dynamic> json) =>
      PrivateSettings.fromJson(jsonEncode(json));

  Map<String, dynamic> written(PrivateSettings settings) =>
      jsonDecode(settings.toJson()) as Map<String, dynamic>;

  final withSignatures = {
    'signatures': [
      {'id': full, 'name': 'Full', 'html': '<p>Alice Real</p>'},
      {'id': short, 'name': 'Short', 'html': '<p>Alice</p>'},
    ],
    'default_signature': {'new': full, 'reply': short},
    'identity_signatures': {
      pseudo: {'new': short},
      bridged: {'new': '', 'reply': ''},
    },
    'identities': ['Alice Real <npub1abc@nostr.mail>', bridged, pseudo],
  };

  group('Signature', () {
    test('keeps the fields it does not know through a rewrite', () {
      final signature = Signature.fromJson({
        'id': full,
        'name': 'Full',
        'html': '<p>Alice</p>',
        'lang': 'fr',
      });

      expect(signature.copyWith(name: 'Long').toJson(), {
        'id': full,
        'name': 'Long',
        'html': '<p>Alice</p>',
        'lang': 'fr',
      });
    });
  });

  group('PrivateSettings signatures', () {
    test('round-trip, with the fields this version does not know', () {
      final images = {
        'abc': {
          'encryption_algorithm': 'aes-gcm',
          'decryption_key': 'a2V5',
          'decryption_nonce': 'bm9uY2U=',
          'mime_type': 'image/png',
          'size': 8231,
          'thumbhash': 'xyz',
        },
      };
      final json = {
        ...withSignatures,
        'default_signature': {'new': full, 'tone': 'formal'},
        'signature_images': images,
      };

      final rewritten = written(settings(json).copyWith(bridges: ['x.com']));

      expect(rewritten['signatures'], json['signatures']);
      expect(rewritten['default_signature'], json['default_signature']);
      expect(rewritten['identity_signatures'], json['identity_signatures']);
      expect(rewritten['signature_images'], images);
    });

    test('writes identities back as they were read', () {
      final identities = [
        'Alice Real <npub1abc@nostr.mail>',
        bridged,
        'Élodie <e@x.com>',
      ];
      final read = settings({'identities': identities});

      expect(written(read.copyWith(bridges: []))['identities'], identities);
      expect(
        written(
          read.copyWith(
            identities: [
              ...read.identities!.reversed,
              MailAddress('Bob', 'bob@x.com'),
              MailAddress('Doe, John', 'j@x.com'),
              MailAddress(null, 'c@x.com'),
            ],
          ),
        )['identities'],
        [
          ...identities.reversed,
          'Bob <bob@x.com>',
          '"Doe, John" <j@x.com>',
          'c@x.com',
        ],
      );
    });

    test('an identity takes its own choice, field by field over the '
        'default', () {
      final s = settings(withSignatures);
      final alice = s.identities![0];
      final npub = s.identities![1];
      final pseudoAddress = MailAddress.parse(pseudo);

      expect(s.signatureFor(alice)?.id, full);
      expect(s.signatureFor(alice, reply: true)?.id, short);
      expect(s.signatureFor(pseudoAddress)?.id, short);
      expect(s.signatureFor(pseudoAddress, reply: true)?.id, short);
      expect(s.signatureFor(npub), isNull);
      expect(s.signatureFor(npub, reply: true), isNull);
      expect(s.signatureFor(MailAddress('Other', 'o@x.com'))?.id, full);
    });

    test('an unknown id, or no default, gives no signature', () {
      final s = settings({
        ...withSignatures,
        'default_signature': {'new': 'ffffffffffffffff'},
      });

      expect(s.signatureFor(MailAddress(null, 'o@x.com')), isNull);
      expect(s.signatureFor(MailAddress(null, 'o@x.com'), reply: true), isNull);
    });

    test('without signatures, nothing is chosen', () {
      final s = settings({
        'signature': 'Sent via Nostr Mail',
        'default_signature': {'new': full},
      });

      expect(s.signatureFor(MailAddress(null, 'o@x.com')), isNull);
      expect(s.signature, 'Sent via Nostr Mail');
    });
  });
}
