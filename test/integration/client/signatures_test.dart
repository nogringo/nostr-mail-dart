import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:sembast/sembast_memory.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';
import '../../helpers/test_database.dart';
import '../../helpers/test_sync_engine.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('Signatures', () {
    late Ndk ndk;
    late NostrMailClient client;
    late MockRelay relay;

    final alice = MailAddress('Alice', 'alice@example.com');
    final pseudo = MailAddress('Pseudo', 'pseudo@example.com');

    setUp(() async {
      relay = MockRelay(name: 'relay');
      await relay.startServer();

      final db = await databaseFactoryMemory.openDatabase(
        'test_db_${DateTime.now().microsecondsSinceEpoch}',
      );
      ndk = Ndk(
        NdkConfig(
          bootstrapRelays: [relay.url],
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
        ),
      );

      final keyPair = Bip340.generatePrivateKey();
      ndk.accounts.loginPrivateKey(
        pubkey: keyPair.publicKey,
        privkey: keyPair.privateKey!,
      );

      client = await NostrMailClient.create(
        ndk: ndk,
        database: testDatabase(),
        db: db,
        syncEngine: testSyncEngine(ndk, db),
        blossomCache: await openTestBlossomCache('signatures_test'),
        indexerRelays: [relay.url],
        defaultNip65Relays: [relay.url],
      );
    });

    tearDown(() async {
      await ndk.destroy();
      await relay.stopServer();
    });

    PrivateSettings settings() => client.cachedPrivateSettings()!;

    test('creates, updates and deletes signatures', () async {
      final full = await client.createSignature(' Full ', html: '<p>A</p>');
      final short = await client.createSignature('Short', html: '<p>B</p>');

      expect(full.id, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(full.name, 'Full');
      expect(
        () => client.createSignature('short', html: ''),
        throwsA(isA<NostrMailException>()),
      );
      expect(
        () => client.updateSignature(short.id, name: 'FULL'),
        throwsA(isA<NostrMailException>()),
      );

      await client.updateSignature(short.id, html: '<p>C</p>');
      expect(settings().signatures!.map((s) => s.html), [
        '<p>A</p>',
        '<p>C</p>',
      ]);

      await client.deleteSignature(full.id);
      expect(settings().signatures!.map((s) => s.id), [short.id]);
    });

    test('chooses per identity, over the default', () async {
      await client.updatePrivateSettings(identities: [alice, pseudo]);
      final full = await client.createSignature('Full', html: '<p>A</p>');
      final short = await client.createSignature('Short', html: '<p>B</p>');

      await client.setDefaultSignature(
        SignatureChoice(newEmail: full.id, reply: short.id),
      );
      await client.setIdentitySignature(
        pseudo,
        SignatureChoice(newEmail: short.id),
      );

      expect(settings().signatureFor(alice)?.id, full.id);
      expect(settings().signatureFor(pseudo)?.id, short.id);
      expect(settings().signatureFor(pseudo, reply: true)?.id, short.id);
      expect(settings().identitySignatures!.keys, [
        'Pseudo <pseudo@example.com>',
      ]);

      await client.setIdentitySignature(pseudo, null);
      expect(settings().signatureFor(pseudo)?.id, full.id);

      expect(
        () => client.setIdentitySignature(
          MailAddress(null, 'nobody@example.com'),
          const SignatureChoice(newEmail: ''),
        ),
        throwsA(isA<NostrMailException>()),
      );
    });

    test('renaming an identity moves its choice', () async {
      await client.updatePrivateSettings(identities: [alice, pseudo]);
      final short = await client.createSignature('Short', html: '<p>B</p>');
      await client.setIdentitySignature(
        pseudo,
        SignatureChoice(newEmail: short.id),
      );

      final renamed = MailAddress('Mask', 'pseudo@example.com');
      await client.renameIdentity(pseudo, renamed);

      expect(settings().identities!.map((e) => e.personalName), [
        'Alice',
        'Mask',
      ]);
      expect(settings().identitySignatures!.keys, [
        'Mask <pseudo@example.com>',
      ]);
      expect(settings().signatureFor(renamed)?.id, short.id);
      expect(
        () => client.renameIdentity(renamed, alice),
        throwsA(isA<NostrMailException>()),
      );
    });
  });
}
