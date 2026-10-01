import 'dart:convert';

import 'package:ndk/ndk.dart' show Nip01Event;
import 'package:nostr_mail/src/utils/senders_list.dart';
import 'package:test/test.dart';

void main() {
  Nip01Event event({List<List<String>> tags = const []}) => Nip01Event(
    pubKey: 'pk',
    kind: 1990,
    tags: [
      ['d', 'nostr-mail/senders'],
      ...tags,
    ],
    content: 'ciphertext',
    createdAt: 1000,
  );

  group('sendersListEntries', () {
    test('reads the sender tuples of the plaintext', () {
      final plaintext = jsonEncode([
        ['sender', 'pk1', 'allow'],
        ['sender', 'bridge:alice@example.com', 'block'],
      ]);

      expect(sendersListEntries(event(), plaintext), [
        (key: 'pk1', verdict: 'allow'),
        (key: 'bridge:alice@example.com', verdict: 'block'),
      ]);
    });

    test('adds the sender tags of the event', () {
      final plaintext = jsonEncode([
        ['sender', 'pk1', 'allow'],
      ]);
      final withTags = event(
        tags: [
          ['sender', 'pk2', 'block'],
        ],
      );

      expect(sendersListEntries(withTags, plaintext), [
        (key: 'pk2', verdict: 'block'),
        (key: 'pk1', verdict: 'allow'),
      ]);
    });

    test('keeps an unknown verdict, or none, as published', () {
      final plaintext = jsonEncode([
        ['sender', 'pk1', 'maybe'],
        ['sender', 'pk2'],
      ]);

      expect(sendersListEntries(event(), plaintext), [
        (key: 'pk1', verdict: 'maybe'),
        (key: 'pk2', verdict: null),
      ]);
    });

    test('keeps the first entry of a key named twice', () {
      final plaintext = jsonEncode([
        ['sender', 'pk1', 'allow'],
        ['sender', 'pk1', 'block'],
      ]);

      expect(sendersListEntries(event(), plaintext), [
        (key: 'pk1', verdict: 'allow'),
      ]);
    });

    test('skips what is not a sender tuple', () {
      final plaintext = jsonEncode([
        ['p', 'pk1'],
        ['sender'],
        ['sender', 42, 'allow'],
        'sender',
        ['sender', 'pk2', 'allow'],
      ]);

      expect(sendersListEntries(event(), plaintext), [
        (key: 'pk2', verdict: 'allow'),
      ]);
    });

    test('reads nothing from a malformed plaintext', () {
      expect(sendersListEntries(event(), 'not json'), isEmpty);
      expect(sendersListEntries(event(), '{"sender": "pk1"}'), isEmpty);
      expect(sendersListEntries(event(), ''), isEmpty);
    });
  });

  test('sendersListContent round-trips through sendersListEntries', () {
    const entries = [
      (key: 'pk1', verdict: 'allow'),
      (key: 'pk2', verdict: null),
    ];
    final content = sendersListContent(entries);

    expect(jsonDecode(content), [
      ['sender', 'pk1', 'allow'],
      ['sender', 'pk2'],
    ]);
    expect(sendersListEntries(event(), content), entries);
  });
}
