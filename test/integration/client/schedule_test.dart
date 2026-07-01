import 'package:ndk/ndk.dart';
import 'package:ndk/entities.dart' show ReadWriteMarker;
import 'package:ndk/shared/nips/nip01/bip340.dart';
import 'package:nostr_event_scheduler/nostr_event_scheduler.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

void main() {
  test(
    'schedule an email: dated at the schedule time, listable and cancelable',
    () async {
      final relay = MockRelay(name: 'relay', explicitPort: 19030);
      await relay.startServer();
      addTearDown(() async => await relay.stopServer());

      final dvm = Bip340.generatePrivateKey();
      final recipient = Bip340.generatePrivateKey();

      final sender = await TestUser(
        'scheduler sender',
        defaultDmRelays: [relay.url],
        schedulerDvm: dvm.publicKey,
        schedulerDvmReadRelays: [relay.url],
      ).create();
      addTearDown(() async => await sender.destroy());

      // The scheduler broadcasts the request/manifest to the user's NIP-65 relays.
      await sender.ndk.userRelayLists.broadcastAddNip65Relay(
        relayUrl: relay.url,
        marker: ReadWriteMarker.readWrite,
        broadcastRelays: [relay.url],
      );

      const twoDays = 2 * 24 * 60 * 60;
      final at = DateTime.now().add(const Duration(days: 30));
      final atEpoch = at.millisecondsSinceEpoch ~/ 1000;
      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

      final scheduled = await sender.client.scheduleEmail(
        to: [NostrRecipient.fromPubkey(recipient.publicKey)],
        subject: 'meeting monday',
        body: 'see you monday at 8',
        at: at,
      );

      // The returned ScheduledEmail reflects the display context.
      expect(scheduled.subject, 'meeting monday');
      expect(scheduled.scheduleAt.millisecondsSinceEpoch ~/ 1000, atEpoch);
      expect(scheduled.status, ScheduledEmailStatus.pending);
      expect(scheduled.isPublic, isFalse);
      expect(
        scheduled.to,
        contains('${Nip19.encodePubKey(recipient.publicKey)}@nostr'),
      );
      expect(scheduled.bodyPreview, contains('see you monday'));

      final list = await sender.client.getScheduledEmails();
      expect(list, hasLength(1));
      expect(list.single.packageId, scheduled.packageId);

      // Read the raw scheduled package over the same db to inspect the events the
      // DVM will publish.
      final inspector = EventScheduler(
        ndk: sender.ndk,
        broadcast: sender.client.broadcastQueue,
        db: sender.db,
      );
      addTearDown(() async => await inspector.dispose());

      final packages = await inspector.listPackages();
      expect(packages, hasLength(1));
      final pkg = packages.single;

      // One DVM job per outgoing gift wrap: the recipient plus the sender's own
      // copy (keepCopy defaults to true).
      expect(pkg.jobs, hasLength(2));
      for (final job in pkg.jobs) {
        expect(job.targetEvent.kind, giftWrapKind);
        expect(job.scheduleAt, atEpoch);
        expect(job.dvmPubkey, dvm.publicKey);
        // Privacy: the visible envelope is dated in the 2 days before the schedule
        // time, never "now" and never in the future.
        expect(job.targetEvent.createdAt, lessThan(atEpoch));
        expect(
          job.targetEvent.createdAt,
          greaterThanOrEqualTo(atEpoch - twoDays - 1),
        );
        expect(job.targetEvent.createdAt, greaterThan(now));
      }

      // The sender's own gift wrap unwraps to a rumor dated exactly at the
      // schedule time, which is what the recipient sees as the send date.
      final selfJob = pkg.jobs.firstWhere(
        (j) => j.targetEvent.getFirstTag('p') == sender.keyPair.publicKey,
      );
      final rumor = await sender.ndk.giftWrap.fromGiftWrap(
        giftWrap: selfJob.targetEvent,
      );
      expect(rumor.kind, emailKind);
      expect(rumor.createdAt, atEpoch);

      // What the recipient's client shows is Email.date, which reads the MIME
      // Date header. It must be the schedule time, not when the email was
      // composed.
      final received = Email(
        id: rumor.id,
        senderPubkey: rumor.pubKey,
        recipientPubkey: sender.keyPair.publicKey,
        lightMimeText: rumor.content,
        attachmentRefs: const [],
        createdAt: DateTime.fromMillisecondsSinceEpoch(rumor.createdAt * 1000),
        isBridged: false,
      );
      expect(received.date.millisecondsSinceEpoch ~/ 1000, atEpoch);

      // Cancelling removes it from the client and from the store.
      await sender.client.cancelScheduledEmail(scheduled.packageId);
      expect(await sender.client.getScheduledEmails(), isEmpty);
      expect(await inspector.listPackages(), isEmpty);
    },
  );
}
