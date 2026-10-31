import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/ndk.dart';
import 'package:ndk/shared/nips/nip01/key_pair.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../helpers/wait_for_broadcasts.dart';
import '../../mocks/mock_relay.dart';

void main() {
  late MockRelay dmRelay;
  late MockRelay nip65Relay;

  setUp(() async {
    dmRelay = MockRelay(name: 'default_dm');
    await dmRelay.startServer();
    addTearDown(() async => await dmRelay.stopServer());
    nip65Relay = MockRelay(name: 'default_nip65');
    await nip65Relay.startServer();
    addTearDown(() async => await nip65Relay.stopServer());
  });

  Future<TestUser> device(String name, {KeyPair? keyPair}) async {
    final user = await TestUser(
      '${name}_${DateTime.now().microsecondsSinceEpoch}',
      defaultDmRelays: [dmRelay.url],
      defaultNip65Relays: [nip65Relay.url],
      publishesRelayLists: false,
      keyPair: keyPair,
    ).create();
    addTearDown(() async => await user.destroy());
    return user;
  }

  test(
    'an account without NIP-65 writes on the default NIP-65 relays',
    () async {
      final phone = await device('phone');
      final me = phone.keyPair.publicKey;

      await phone.client.setPrivateSettings(
        const PrivateSettings(signature: 'Cheers'),
      );
      final draft = await phone.client.saveDraft(
        (MessageBuilder()
              ..from = [MailAddress(null, 'me@example.com')]
              ..subject = 'Plans'
              ..text = 'Hello')
            .buildMimeMessage(),
      );
      await waitForBroadcasts(phone.client.broadcastQueue);

      final filter = Filter(
        kinds: [appSettingsKind, draftWrapKind],
        authors: [me],
      );
      expect(nip65Relay.matchingEvents(filter), hasLength(2));
      expect(dmRelay.matchingEvents(filter), isEmpty);

      final laptop = await device('laptop', keyPair: phone.keyPair);
      await laptop.client.fetchRecent();
      expect((await laptop.client.fetchPrivateSettings())!.signature, 'Cheers');
      expect((await laptop.client.getDrafts()).single.draftId, draft.draftId);
    },
  );
}
