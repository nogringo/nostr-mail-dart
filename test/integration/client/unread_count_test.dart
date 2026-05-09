import 'package:nostr_mail/src/storage/email_repository.dart';
import 'package:nostr_mail/src/storage/models/email_record.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_blossom_server.dart';
import '../../mocks/mock_relay.dart';

void main() {
  group('NostrMailClient unread count', () {
    late MockRelay relay;
    late MockBlossomServer blossom;
    late TestUser user;
    late EmailRepository emailRepo;

    setUp(() async {
      relay = MockRelay(name: 'relay', explicitPort: 19010);
      await relay.startServer();

      blossom = MockBlossomServer(port: 3458);
      await blossom.start();

      user = await TestUser(
        'unread-count-${DateTime.now().microsecondsSinceEpoch}',
        defaultDmRelays: [relay.url],
        defaultBlossomServers: ['http://localhost:${blossom.port}'],
      ).create();

      emailRepo = EmailRepository(user.db);
    });

    tearDown(() async {
      await user.destroy();
      await blossom.stop();
      await relay.stopServer();
    });

    EmailRecord makeRecord(
      String id, {
      required String folder,
      required bool isRead,
    }) {
      final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      return EmailRecord(
        id: id,
        senderPubkey: 'sender-pubkey',
        recipientPubkey: user.keyPair.publicKey,
        rawContent: 'From: a@b.com\r\nSubject: T\r\n\r\nBody',
        isPublic: false,
        createdAt: ts,
        date: ts,
        from: 'a@b.com',
        subject: 'T',
        bodyPlain: 'Body',
        searchText: 'a@b.com t body',
        attachmentCount: 0,
        folder: folder,
        isRead: isRead,
        isStarred: false,
        labels: const [],
        isBridged: false,
      );
    }

    test('getUnreadCount returns total unread per folder', () async {
      await emailRepo.save(makeRecord('i1', folder: 'inbox', isRead: false));
      await emailRepo.save(makeRecord('i2', folder: 'inbox', isRead: false));
      await emailRepo.save(makeRecord('i3', folder: 'inbox', isRead: true));
      await emailRepo.save(makeRecord('a1', folder: 'archive', isRead: false));

      expect(await user.client.getUnreadCount(folder: 'inbox'), 2);
      expect(await user.client.getUnreadCount(folder: 'archive'), 1);
      expect(await user.client.getUnreadCount(folder: 'trash'), 0);
      expect(await user.client.getUnreadCount(), 3); // all folders
    });

    test(
      'watchUnreadCount emits initial value then updates on markAsRead',
      () async {
        await emailRepo.save(makeRecord('i1', folder: 'inbox', isRead: false));
        await emailRepo.save(makeRecord('i2', folder: 'inbox', isRead: false));

        final emissions = <int>[];
        final sub = user.client
            .watchUnreadCount(folder: 'inbox')
            .listen(emissions.add);

        await Future.delayed(const Duration(milliseconds: 100));
        expect(emissions, [2]);

        await user.client.markAsRead('i1');
        await Future.delayed(const Duration(milliseconds: 100));
        expect(emissions, [2, 1]);

        await user.client.markAsUnread('i1');
        await Future.delayed(const Duration(milliseconds: 100));
        expect(emissions, [2, 1, 2]);

        await sub.cancel();
      },
    );

    test('watchUnreadCount supports multiple concurrent subscribers', () async {
      await emailRepo.save(makeRecord('i1', folder: 'inbox', isRead: false));
      await emailRepo.save(makeRecord('i2', folder: 'inbox', isRead: false));

      final stream = user.client.watchUnreadCount(folder: 'inbox');
      final emissionsA = <int>[];
      final emissionsB = <int>[];
      final subA = stream.listen(emissionsA.add);
      final subB = stream.listen(emissionsB.add);

      await Future.delayed(const Duration(milliseconds: 100));
      expect(emissionsA, [2]);
      expect(emissionsB, [2]);

      await user.client.markAsRead('i1');
      await Future.delayed(const Duration(milliseconds: 100));
      expect(emissionsA, [2, 1]);
      expect(emissionsB, [2, 1]);

      await subA.cancel();
      await subB.cancel();
    });
  });
}
