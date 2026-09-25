import 'dart:convert';

import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

void main() {
  group('MailEntry', () {
    test('keeps the fields it does not know through a rewrite', () {
      final entry = MailEntry.fromJson({
        'id': '9f2c1a7b4d3e5f60',
        'name': 'Invoices',
        'icon': 'receipt',
        'match': {
          'from': ['billing.example.com'],
          'body': ['invoice'],
        },
      });

      final json = entry.copyWith(name: 'Bills').toJson();

      expect(json['name'], 'Bills');
      expect(json['icon'], 'receipt');
      expect(json['match'], {
        'from': ['billing.example.com'],
        'body': ['invoice'],
      });
      expect(json.containsKey('color'), isFalse);
      expect(json.containsKey('position'), isFalse);
    });

    test('sorts by position, entries without one last, ties by name', () {
      final sorted = sortEntries(const [
        MailEntry(id: 'a', name: 'Zeta'),
        MailEntry(id: 'b', name: 'Beta', position: 1),
        MailEntry(id: 'c', name: 'Alpha'),
        MailEntry(id: 'd', name: 'Delta', position: 0),
        MailEntry(id: 'e', name: 'Alpha', position: 1),
      ]);

      expect(sorted.map((e) => e.id), ['d', 'e', 'b', 'c', 'a']);
    });
  });

  group('MailMatch', () {
    test('keeps the fields it does not know through copyWith', () {
      final match = MailMatch.fromJson({
        'from': ['billing.example.com'],
        'body': ['invoice'],
      });

      final json = match
          .copyWith(subject: ['Invoice'], clearFrom: true)
          .toJson();

      expect(json, {
        'subject': ['Invoice'],
        'body': ['invoice'],
      });
    });

    bool matches(
      MailMatch match, {
      String from = 'someone@example.com',
      String subject = '',
      bool hasAttachment = false,
    }) => match.matches(
      from: from,
      subject: subject,
      hasAttachment: hasAttachment,
    );

    test('from matches the address, its domain and its parent domains', () {
      const github = MailMatch(from: ['GitHub.com']);

      expect(matches(github, from: 'github.com'), isTrue);
      expect(matches(github, from: 'noreply@github.com'), isTrue);
      expect(matches(github, from: 'a@mail.GITHUB.com'), isTrue);
      expect(matches(github, from: 'a@notgithub.com'), isFalse);
      expect(matches(github, from: 'github.com@evil.org'), isFalse);

      const address = MailMatch(from: ['alice@example.com']);
      expect(matches(address, from: 'Alice@Example.com'), isTrue);
      expect(matches(address, from: 'malice@example.com'), isFalse);
    });

    test('subject is a case-insensitive substring, beyond ASCII', () {
      const facture = MailMatch(subject: ['FACTURÉE']);

      expect(matches(facture, subject: 'Votre commande facturée'), isTrue);
      expect(matches(facture, subject: 'Votre commande'), isFalse);
    });

    test('has_attachment false matches emails without one', () {
      const none = MailMatch(hasAttachment: false);

      expect(matches(none), isTrue);
      expect(matches(none, hasAttachment: true), isFalse);
    });

    test('fields combine with AND, entries of a field with OR', () {
      const match = MailMatch(from: ['a.com', 'b.com'], subject: ['invoice']);

      expect(matches(match, from: 'x@b.com', subject: 'Invoice 42'), isTrue);
      expect(matches(match, from: 'x@b.com', subject: 'Hello'), isFalse);
      expect(matches(match, from: 'x@c.com', subject: 'Invoice'), isFalse);
    });

    test('a match with no field matches nothing', () {
      expect(matches(const MailMatch()), isFalse);
    });
  });

  group('PrivateSettings folders and tags', () {
    test('round-trip, with the top-level fields it does not know', () {
      final json = jsonEncode({
        'signature': 'sig',
        'theme': 'dark',
        'folders': [
          {'id': '9f2c1a7b4d3e5f60', 'name': 'Invoices', 'position': 0},
        ],
        'tags': [
          {'id': '4b81d0e7a5c39f12', 'name': 'Urgent', 'color': '#C86432'},
        ],
      });

      final settings = PrivateSettings.fromJson(json);
      expect(settings.folders!.single.name, 'Invoices');
      expect(settings.tags!.single.color, '#C86432');

      final rewritten =
          jsonDecode(settings.copyWith(signature: 'new').toJson())
              as Map<String, dynamic>;
      expect(rewritten['theme'], 'dark');
      expect(rewritten['signature'], 'new');
      expect((rewritten['folders'] as List).single['id'], '9f2c1a7b4d3e5f60');
      expect((rewritten['tags'] as List).single['name'], 'Urgent');
    });
  });
}
