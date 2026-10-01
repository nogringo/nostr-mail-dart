import 'dart:convert';

import 'package:ndk/ndk.dart'
    show Bip340EventSigner, Nip01Event, Nip01EventModel;
import 'package:ndk/shared/nips/nip01/bip340.dart';
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

  group('sendersListBatches', () {
    test('keeps a short list in one batch', () {
      const entries = [
        (key: 'pk1', verdict: 'allow'),
        (key: 'pk2', verdict: 'block'),
      ];

      expect(sendersListBatches(entries), [entries]);
      expect(sendersListBatches(const []), isEmpty);
    });

    test(
      'splits a long list into events of at most 64 KiB, in order',
      () async {
        final keyPair = Bip340.generatePrivateKey();
        final signer = Bip340EventSigner(
          privateKey: keyPair.privateKey,
          publicKey: keyPair.publicKey,
        );
        final entries = [
          for (var i = 0; i < 1000; i++)
            (key: i.toRadixString(16).padLeft(64, '0'), verdict: 'block'),
        ];

        final batches = sendersListBatches(entries);

        expect(batches, hasLength(3));
        expect(batches.expand((batch) => batch), entries);
        for (final batch in batches) {
          final content = await signer.encryptNip44(
            plaintext: sendersListContent(batch),
            recipientPubKey: keyPair.publicKey,
          );
          final signed = await signer.sign(
            Nip01Event(
              pubKey: keyPair.publicKey,
              kind: 1990,
              tags: [
                ['d', 'nostr-mail/senders'],
              ],
              content: content!,
              createdAt: 1000,
            ),
          );
          final json = Nip01EventModel.fromEntity(signed).toJsonString();
          expect(utf8.encode(json).length, lessThanOrEqualTo(64 * 1024));
        }
      },
    );
  });
}
