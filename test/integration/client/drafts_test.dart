import 'dart:convert';
import 'dart:typed_data';

import 'package:blossom_upload_queue_shim_for_ndk/blossom_upload_queue_shim_for_ndk.dart';
import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_blossom_server.dart';
import '../../mocks/mock_relay.dart';

void main() {
  late MockRelay relay;
  late MockBlossomServer blossom;
  late TestUser phone;
  late TestUser desktop;
  late String me;

  setUp(() async {
    relay = MockRelay(name: 'drafts');
    await relay.startServer();
    addTearDown(() async => await relay.stopServer());
    blossom = MockBlossomServer(port: 3459);
    await blossom.start();
    addTearDown(() async => await blossom.stop());

    final suffix = DateTime.now().microsecondsSinceEpoch;
    final servers = ['http://localhost:${blossom.port}'];
    phone = await TestUser(
      'drafts_phone_$suffix',
      defaultDmRelays: [relay.url],
      defaultBlossomServers: servers,
    ).create();
    addTearDown(() async => await phone.destroy());
    desktop = await TestUser(
      'drafts_desktop_$suffix',
      defaultDmRelays: [relay.url],
      defaultBlossomServers: servers,
      keyPair: phone.keyPair,
    ).create();
    addTearDown(() async => await desktop.destroy());
    me = phone.keyPair.publicKey;
  });

  MimeMessage message(String subject, {Uint8List? attachment}) {
    final builder = MessageBuilder.prepareMultipartMixedMessage()
      ..from = [MailAddress(null, 'me@example.com')]
      ..to = [MailAddress('Bob', 'bob@example.com')]
      ..bcc = [MailAddress(null, 'carol@example.com')]
      ..subject = subject
      ..addTextPlain('Hello Bob');
    if (attachment != null) {
      builder.addBinary(
        attachment,
        MediaType.fromText('application/octet-stream'),
        filename: 'big.bin',
      );
    }
    return builder.buildMimeMessage();
  }

  /// The current version of each draft on [relay], by `d`.
  Map<String, Nip01Event> wrapsOn(MockRelay relay) {
    final latest = <String, Nip01Event>{};
    for (final wrap in relay.matchingEvents(
      Filter(kinds: [draftWrapKind], authors: [me]),
    )) {
      final d = wrap.getDtag()!;
      final current = latest[d];
      if (current == null || wrap.createdAt > current.createdAt) {
        latest[d] = wrap;
      }
    }
    return latest;
  }

  Future<Map<String, dynamic>> rumorOf(Nip01Event wrap) async {
    final plaintext = await phone.ndk.accounts
        .getLoggedAccount()!
        .signer
        .decryptNip44(ciphertext: wrap.content, senderPubKey: me);
    return jsonDecode(plaintext!) as Map<String, dynamic>;
  }

  test('a draft reaches the other device', () async {
    final draft = await phone.client.saveDraft(message('Plans'));
    await waitForBroadcasts(phone.client.broadcastQueue);

    expect(draft.draftId, matches(RegExp(r'^[0-9a-f]{32}$')));
    expect(draft.subject, 'Plans');
    expect(draft.to, ['bob@example.com']);
    expect(draft.bcc, ['carol@example.com']);
    expect(await phone.client.getDrafts(), [draft]);

    final wrap = wrapsOn(relay)[draft.draftId]!;
    expect(wrap.tags, [
      ['d', draft.draftId],
      ['k', '1301'],
    ]);
    expect(wrap.content, isNot(contains('Plans')));

    await desktop.client.fetchRecent();
    final synced = (await desktop.client.getDrafts()).single;
    expect(synced.draftId, draft.draftId);
    expect(synced.subject, 'Plans');
    expect(synced.bodyPreview, contains('Hello Bob'));

    final mime = (await desktop.client.getDraftMime(draft.draftId))!;
    expect(mime.decodeSubject(), 'Plans');
    expect(mime.bcc!.single.email, 'carol@example.com');
  });

  test('the rumor is the unsigned self-copy', () async {
    final draft = await phone.client.saveDraft(message('Plans'));
    await waitForBroadcasts(phone.client.broadcastQueue);

    final rumor = await rumorOf(wrapsOn(relay)[draft.draftId]!);
    expect(rumor.containsKey('sig'), isFalse);
    expect(rumor['kind'], emailKind);
    expect(rumor['pubkey'], me);
    expect(rumor['tags'], [
      ['p', me],
    ]);
    expect(rumor['content'], contains('carol@example.com'));
  });

  test('a save replaces the previous version', () async {
    final first = await phone.client.saveDraft(message('Plans'));
    final second = await phone.client.saveDraft(
      message('Plans for Friday'),
      draftId: first.draftId,
    );

    expect(second.updatedAt.isAfter(first.updatedAt), isTrue);
    expect((await phone.client.getDrafts()).single.subject, 'Plans for Friday');

    await waitForBroadcasts(phone.client.broadcastQueue);

    await desktop.client.fetchRecent();
    final synced = (await desktop.client.getDrafts()).single;
    expect(synced.subject, 'Plans for Friday');
  });

  test('a deleted draft is gone on every device', () async {
    final draft = await phone.client.saveDraft(message('Plans'));
    await waitForBroadcasts(phone.client.broadcastQueue);
    await desktop.client.fetchRecent();
    expect(await desktop.client.getDrafts(), hasLength(1));

    await phone.client.deleteDraft(draft.draftId);
    await waitForBroadcasts(phone.client.broadcastQueue);

    expect(await phone.client.getDrafts(), isEmpty);
    expect(await phone.client.getDraftMime(draft.draftId), isNull);
    expect(wrapsOn(relay)[draft.draftId]!.content, isEmpty);

    await desktop.client.fetchRecent();
    expect(await desktop.client.getDrafts(), isEmpty);
  });

  test('a large draft travels as a Blossom blob', () async {
    final attachment = Uint8List.fromList(
      List.generate(64 * 1024, (i) => i % 256),
    );
    final draft = await phone.client.saveDraft(
      message('Big', attachment: attachment),
    );
    expect(draft.attachmentNames, ['big.bin']);
    await waitForBroadcasts(phone.client.broadcastQueue);
    while ((await phone.client.blossomUploadQueue.listAll()).any(
      (u) => u.status != BlobUploadStatus.delivered,
    )) {
      await Future.delayed(const Duration(milliseconds: 50));
    }

    final rumor = await rumorOf(wrapsOn(relay)[draft.draftId]!);
    expect(rumor['content'], isEmpty);
    expect(
      (rumor['tags'] as List).map((t) => (t as List).first),
      containsAll(['x', 'decryption-key', 'decryption-nonce']),
    );

    await desktop.client.fetchRecent();
    expect((await desktop.client.getDrafts()).single.attachmentNames, [
      'big.bin',
    ]);
    final mime = (await desktop.client.getDraftMime(draft.draftId))!;
    final part = mime.allPartsFlat.firstWhere(
      (p) => p.decodeFileName() == 'big.bin',
    );
    expect(part.decodeContentBinary(), attachment);
  });

  /// A private relay listed in the account's kind 10013.
  Future<MockRelay> listPrivateRelay() async {
    final private = MockRelay(name: 'drafts_private');
    await private.startServer();
    addTearDown(() async => await private.stopServer());

    final signer = phone.ndk.accounts.getLoggedAccount()!.signer;
    final list = await signer.sign(
      Nip01Event(
        pubKey: me,
        kind: privateRelayListKind,
        tags: const [],
        content: (await signer.encryptNip44(
          plaintext: jsonEncode([
            ['relay', private.url],
          ]),
          recipientPubKey: me,
        ))!,
      ),
    );
    await phone.ndk.broadcast
        .broadcast(nostrEvent: list, specificRelays: [relay.url])
        .broadcastDoneFuture;
    return private;
  }

  test('drafts go to the private relays when the account has some', () async {
    final private = await listPrivateRelay();

    final draft = await phone.client.saveDraft(message('Plans'));
    await waitForBroadcasts(phone.client.broadcastQueue);

    expect(wrapsOn(private).keys, [draft.draftId]);
    expect(wrapsOn(relay), isEmpty);

    await desktop.client.fetchRecent();
    expect((await desktop.client.getDrafts()).single.draftId, draft.draftId);
  });

  test('drafts left on the write relays are still read', () async {
    final kept = await phone.client.saveDraft(message('Kept'));
    final gone = await phone.client.saveDraft(message('Gone'));
    await waitForBroadcasts(phone.client.broadcastQueue);

    final private = await listPrivateRelay();
    await phone.client.deleteDraft(gone.draftId);
    final fresh = await phone.client.saveDraft(message('Fresh'));
    await waitForBroadcasts(phone.client.broadcastQueue);

    expect(wrapsOn(relay).keys, unorderedEquals([kept.draftId, gone.draftId]));
    expect(
      wrapsOn(private).keys,
      unorderedEquals([gone.draftId, fresh.draftId]),
    );

    // Logged in once the list exists: a device that checked it before
    // trusts the absence for an hour.
    final laptop = await TestUser(
      'drafts_laptop_${DateTime.now().microsecondsSinceEpoch}',
      defaultDmRelays: [relay.url],
      keyPair: phone.keyPair,
    ).create();
    addTearDown(() async => await laptop.destroy());

    await laptop.client.fetchRecent();
    expect((await laptop.client.getDrafts()).map((d) => d.subject), [
      'Fresh',
      'Kept',
    ]);
  });
}
