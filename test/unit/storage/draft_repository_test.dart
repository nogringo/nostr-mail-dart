import 'package:enough_mail_plus/enough_mail.dart';
import 'package:nostr_mail/src/models/gift_wrap_state.dart';
import 'package:nostr_mail/src/storage/draft_repository.dart';
import 'package:test/test.dart';

import '../../helpers/test_database.dart';

void main() {
  const rpk = 'rpk';
  late DraftRepository repo;

  setUp(() => repo = DraftRepository(testDatabase()));

  MimeMessage message(String subject) =>
      (MessageBuilder()
            ..from = [MailAddress(null, 'me@example.com')]
            ..to = [MailAddress('Bob', 'bob@example.com')]
            ..subject = subject
            ..text = 'Hello Bob')
          .buildMimeMessage();

  Future<void> save(
    String draftId,
    String eventId,
    int createdAt, {
    String? subject,
    String recipientPubkey = rpk,
  }) => repo.saveVersion(
    draftId: draftId,
    recipientPubkey: recipientPubkey,
    eventId: eventId,
    createdAt: createdAt,
    message: subject == null ? null : message(subject),
  );

  test('lists the drafts, most recently saved first', () async {
    await save('a', 'e1', 1, subject: 'First');
    await save('b', 'e2', 2, subject: 'Second');

    final drafts = await repo.list(recipientPubkey: rpk);
    expect(drafts.map((d) => d.draftId), ['b', 'a']);
    expect(drafts.last.subject, 'First');
    expect(drafts.last.to, ['bob@example.com']);
    expect(drafts.last.bodyPreview, 'Hello Bob');
    expect(drafts.last.updatedAt, DateTime.fromMillisecondsSinceEpoch(1000));
  });

  test('a new version replaces the previous one', () async {
    await save('a', 'e1', 1, subject: 'First');
    await save('a', 'e2', 2, subject: 'Edited');

    final drafts = await repo.list(recipientPubkey: rpk);
    expect(drafts.single.subject, 'Edited');
    expect((await repo.get('a', recipientPubkey: rpk))!.eventId, 'e2');
  });

  test('a blank version hides the draft but keeps its row', () async {
    await save('a', 'e1', 1, subject: 'First');
    await save('a', 'e2', 2);

    expect(await repo.list(recipientPubkey: rpk), isEmpty);
    expect(await repo.find('a', recipientPubkey: rpk), isNull);
    expect((await repo.get('a', recipientPubkey: rpk))!.deleted, isTrue);
  });

  test('a failed decryption counts its attempts', () async {
    for (var i = 0; i < 2; i++) {
      await repo.recordFailure(
        eventId: 'e1',
        recipientPubkey: rpk,
        failure: GiftWrapFailure.signer,
      );
    }
    final failed = (await repo.getDecryption('e1', recipientPubkey: rpk))!;
    expect(failed.failure, GiftWrapFailure.signer.name);
    expect(failed.attempts, 2);

    await repo.saveDecryption(
      eventId: 'e1',
      recipientPubkey: rpk,
      plaintext: '{}',
    );
    final decrypted = (await repo.getDecryption('e1', recipientPubkey: rpk))!;
    expect(decrypted.plaintext, '{}');
    expect(decrypted.failure, isNull);
  });

  test('clears one account only', () async {
    await save('a', 'e1', 1, subject: 'Mine');
    await save('b', 'e2', 1, subject: 'Theirs', recipientPubkey: 'other');
    await repo.saveDecryption(
      eventId: 'e1',
      recipientPubkey: rpk,
      plaintext: '{}',
    );

    await repo.clearAll(recipientPubkey: rpk);

    expect(await repo.list(recipientPubkey: rpk), isEmpty);
    expect(await repo.getDecryption('e1', recipientPubkey: rpk), isNull);
    expect(await repo.list(recipientPubkey: 'other'), hasLength(1));
  });
}
