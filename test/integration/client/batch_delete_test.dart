import 'package:ndk/ndk.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/label_repository.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('NostrMailClient.delete', () {
    late MockRelay relay;
    late TestUser user;
    late EmailRepository emails;
    late LabelRepository labels;

    setUp(() async {
      relay = MockRelay(name: 'relay');
      await relay.startServer();

      user = await TestUser(
        'batch-delete-${DateTime.now().microsecondsSinceEpoch}',
        defaultDmRelays: [relay.url],
      ).create();
      emails = EmailRepository(user.db);
      labels = LabelRepository(user.db);
    });

    tearDown(() async {
      await user.destroy();
      await relay.stopServer();
    });

    EmailRecord makeRecord(String id) {
      return EmailRecord(
        id: id,
        senderPubkey: 'sender-pubkey',
        recipientPubkey: user.keyPair.publicKey,
        lightMimeText:
            'From: from@test.com\r\nSubject: Test $id\r\n\r\nTest Body',
        attachmentRefs: const [],
        isPublic: false,
        createdAt: 1000,
        date: 1000,
        from: 'from@test.com',
        subject: 'Test $id',
        bodyPlain: 'Test Body',
        searchText: 'from@test.com test $id test body',
        attachmentCount: 0,
        folder: 'inbox',
        isRead: false,
        isStarred: false,
        labels: const [],
        isBridged: false,
      );
    }

    test('removes local state and broadcasts one deletion event', () async {
      await emails.save(makeRecord('email-1'));
      await emails.save(makeRecord('email-2'));
      await emails.save(makeRecord('email-3'));
      await labels.saveLabel(
        emailId: 'email-1',
        label: 'folder:trash',
        labelEventId: 'label-1',
        timestamp: 1000,
        recipientPubkey: user.keyPair.publicKey,
      );
      await labels.saveLabel(
        emailId: 'email-2',
        label: 'state:read',
        labelEventId: 'label-2',
        timestamp: 1000,
        recipientPubkey: user.keyPair.publicKey,
      );

      await user.client.delete(['email-1', 'email-2']);
      await user.client.flushBroadcasts();

      expect(await user.client.getEmail('email-1'), isNull);
      expect(await user.client.getEmail('email-2'), isNull);
      expect(await user.client.getEmail('email-3'), isNotNull);
      expect(
        await labels.getLabelsForEmail(
          'email-1',
          recipientPubkey: user.keyPair.publicKey,
        ),
        isEmpty,
      );
      expect(
        await labels.getLabelsForEmail(
          'email-2',
          recipientPubkey: user.keyPair.publicKey,
        ),
        isEmpty,
      );

      final deletionEvents = await user.ndk.requests
          .query(
            filter: Filter(
              kinds: [deletionRequestKind],
              authors: [user.keyPair.publicKey],
            ),
            explicitRelays: [relay.url],
          )
          .future;

      expect(deletionEvents, hasLength(1));
      expect(deletionEvents.single.getTags('e').toSet(), {
        'email-1',
        'email-2',
        'label-1',
        'label-2',
      });
      expect(deletionEvents.single.getTags('k').toSet(), {
        giftWrapKind.toString(),
        labelKind.toString(),
      });
    });
  });
}
