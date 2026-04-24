import 'package:nostr_mail/src/services/bridge_resolver.dart';
import 'package:test/test.dart';

void main() {
  test(
    "nip05Overrides overrides NIP-05 routing for bridges and users",
    () async {
      // Three dummy pubkeys (hex format, 64 chars)
      final gmailBridgePubkey =
          '1111111111111111111111111111111111111111111111111111111111111111';
      final primalUserPubkey =
          '2222222222222222222222222222222222222222222222222222222222222222';
      final exampleBridgePubkey =
          '3333333333333333333333333333333333333333333333333333333333333333';

      final resolver = BridgeResolver(
        nip05Overrides: {
          '_smtp@gmail.com': gmailBridgePubkey,
          'bob@primal.net': primalUserPubkey,
          '_smtp@example.com': exampleBridgePubkey,
        },
      );

      expect(await resolver.resolveNip05('_smtp@gmail.com'), gmailBridgePubkey);
      expect(await resolver.resolveNip05('bob@primal.net'), primalUserPubkey);
      expect(
        await resolver.resolveNip05('_smtp@example.com'),
        exampleBridgePubkey,
      );
    },
  );
}
