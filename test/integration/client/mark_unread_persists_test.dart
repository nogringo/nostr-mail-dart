import 'package:test/test.dart';

import '../../helpers/test_user.dart';
import '../../mocks/mock_relay.dart';

/// Regression test for: marking an email as unread and then refreshing
/// causes the email to revert to read.
///
/// Scenario:
/// 1. User marks email as read. A NIP-32 label event L is signed,
///    saved locally, and broadcast to the relay.
/// 2. User marks email as unread. The local label is removed and a
///    NIP-09 deletion event D referencing L is broadcast.
/// 3. The relay does not honor the deletion (real-world: many relays
///    ignore NIP-09, or the deletion has not yet propagated).
/// 4. User refreshes (fetchRecent). The relay still serves L, and the
///    sync engine re-applies it as if it were a fresh label addition,
///    making the email read again.
///
/// The fix: a local tombstone records that L has been deleted, so the
/// sync engine skips L when re-applying label additions.
void main() {
  group('mark unread persists across refetch', () {
    late MockRelay relay;
    late TestUser user;

    setUp(() async {
      relay = MockRelay(
        name: 'relay',
        explicitPort: 19020,
        honorDeletions: false,
      );
      await relay.startServer();

      user = await TestUser(
        'mark-unread-${DateTime.now().microsecondsSinceEpoch}',
        defaultDmRelays: [relay.url],
      ).create();
    });

    tearDown(() async {
      await user.destroy();
      await relay.stopServer();
    });

    test(
      'mark as unread is not reverted when relay re-serves the stale label event',
      () async {
        const emailId = 'test-email-1';

        // 1. Mark as read. Broadcasts a label event L to the relay.
        await user.client.markAsRead(emailId);
        // The broadcast enqueue is fire-and-forget inside addLabel; give
        // it a moment to actually enqueue, then wait for delivery.
        await Future.delayed(const Duration(milliseconds: 50));
        await user.client.flushBroadcasts();
        expect(await user.client.isRead(emailId), isTrue);

        // 2. Mark as unread. Removes the label locally and broadcasts a
        //    deletion event D. The mock relay is configured to ignore
        //    deletions, so L remains stored on the relay.
        await user.client.markAsUnread(emailId);
        await Future.delayed(const Duration(milliseconds: 50));
        await user.client.flushBroadcasts();
        expect(await user.client.isRead(emailId), isFalse);

        // 3. Refresh. fetchRecent re-fetches everything from the relay,
        //    including the stale L. Without a tombstone, onLabelAddition
        //    re-applies L and the email becomes read again.
        await user.client.fetchRecent();

        expect(
          await user.client.isRead(emailId),
          isFalse,
          reason:
              'mark-as-unread must persist across a refetch of the stale label event',
        );
      },
    );
  });
}
