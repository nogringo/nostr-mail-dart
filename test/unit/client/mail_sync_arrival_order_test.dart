// Relays hand back events in whatever order their windows close in, so a
// label or a deletion routinely lands before the email it points at. Both
// have to survive the wait: the label store is read when the row is finally
// created, and a tombstone is recorded even when it matches nothing yet.

import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/client/event_bus.dart';
import 'package:nostr_mail/src/client/mail_sync.dart';
import 'package:nostr_mail/src/client/relay_resolver.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/gift_wrap_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/tombstone_repository.dart';
import 'package:sembast/sembast_memory.dart' hide Filter;
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';
import 'package:test/test.dart';

import '../../helpers/test_blossom_cache.dart';

void main() {
  group('MailSync arrival order', () {
    late Database db;
    late Ndk ndk;
    late EmailRepository emails;
    late LabelRepository labels;
    late SyncEngine engine;
    late MailSync sync;
    late String alice;

    const emailId = 'public-email';

    setUp(() async {
      db = await databaseFactoryMemory.openDatabase(
        'arrival_order_${DateTime.now().microsecondsSinceEpoch}',
      );

      ndk = Ndk(
        NdkConfig(
          eventVerifier: Bip340EventVerifier(),
          cache: MemCacheManager(),
          bootstrapRelays: const [],
        ),
      );

      final aliceKeys = Bip340.generatePrivateKey();
      alice = aliceKeys.publicKey;
      ndk.accounts.loginPrivateKey(
        pubkey: alice,
        privkey: aliceKeys.privateKey!,
      );

      emails = EmailRepository(db);
      labels = LabelRepository(db);
      engine = SyncEngine(ndk, db: db);
      sync = MailSync(
        ndk,
        engine,
        emails,
        labels,
        GiftWrapRepository(db),
        TombstoneRepository(db),
        EventBus(),
        RelayResolver(ndk),
        blossomCache: await openTestBlossomCache('arrival_order_test'),
      );
    });

    tearDown(() async {
      await engine.dispose();
      await ndk.destroy();
      await db.close();
    });

    /// A public email from someone else, so its natural folder is the inbox.
    Nip01Event publicEmail() => Nip01Event(
      id: emailId,
      pubKey: 'sender-pubkey',
      createdAt: 1000,
      kind: emailKind,
      tags: [
        ['p', alice],
      ],
      content: 'From: from@test.com\r\nSubject: Test\r\n\r\nTest Body',
      sig: 'sig',
    );

    Nip01Event labelEvent(String id, String label) => Nip01Event(
      id: id,
      pubKey: alice,
      createdAt: 1000,
      kind: labelKind,
      tags: [
        ['L', labelNamespace],
        ['l', label, labelNamespace],
        ['e', emailId, '', 'labelled'],
      ],
      content: '',
      sig: 'sig',
    );

    Nip01Event deletionOf(String targetId, int kind) => Nip01Event(
      id: 'deletion-of-$targetId',
      pubKey: alice,
      createdAt: 1000,
      kind: deletionRequestKind,
      tags: [
        ['e', targetId],
        ['k', kind.toString()],
      ],
      content: '',
      sig: 'sig',
    );

    test('an email folds in the labels that arrived before it', () async {
      await sync.onLabelAddition(labelEvent('label-trash', 'folder:trash'));
      await sync.onLabelAddition(labelEvent('label-read', 'state:read'));
      await sync.onLabelAddition(labelEvent('label-star', 'flag:starred'));
      await sync.onLabelAddition(labelEvent('label-tag', 'tag:work'));

      await sync.onPublicEmail(publicEmail());

      final record = await emails.getById(emailId, recipientPubkey: alice);
      expect(record, isNotNull);
      expect(record!.folder, 'trash');
      expect(record.isRead, isTrue);
      expect(record.isStarred, isTrue);
      expect(record.labels, ['tag:work']);
    });

    test('an email arriving first keeps the labels applied after it', () async {
      await sync.onPublicEmail(publicEmail());
      await sync.onLabelAddition(labelEvent('label-trash', 'folder:trash'));

      final record = await emails.getById(emailId, recipientPubkey: alice);
      expect(record!.folder, 'trash');
    });

    test('a label deleted before the email ever lands stays off it', () async {
      await sync.onDeletion(deletionOf('label-trash', labelKind));
      await sync.onLabelAddition(labelEvent('label-trash', 'folder:trash'));
      await sync.onPublicEmail(publicEmail());

      final record = await emails.getById(emailId, recipientPubkey: alice);
      expect(record!.folder, 'inbox');
      expect(
        await labels.getLabelsForEmail(emailId, recipientPubkey: alice),
        isEmpty,
      );
    });

    test('a label deleted after it landed but before the email', () async {
      await sync.onLabelAddition(labelEvent('label-trash', 'folder:trash'));
      await sync.onDeletion(deletionOf('label-trash', labelKind));
      await sync.onPublicEmail(publicEmail());

      final record = await emails.getById(emailId, recipientPubkey: alice);
      expect(record!.folder, 'inbox');
    });

    test('an email deleted before it arrives is never stored', () async {
      await sync.onDeletion(deletionOf(emailId, emailKind));
      await sync.onPublicEmail(publicEmail());

      expect(await emails.getById(emailId, recipientPubkey: alice), isNull);
    });
  });
}
