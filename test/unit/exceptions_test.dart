import 'package:nostr_mail/nostr_mail.dart';
import 'package:test/test.dart';

void main() {
  group('Exceptions', () {
    test('NostrMailException has correct message', () {
      final exception = NostrMailException('Test error');

      expect(exception.message, 'Test error');
      expect(exception.toString(), 'NostrMailException: Test error');
    });

    test('BridgeResolutionException includes domain', () {
      final exception = BridgeResolutionException('example.com');

      expect(exception.toString(), contains('example.com'));
    });

    test('RecipientResolutionException includes recipient', () {
      final exception = RecipientResolutionException('bad@email');

      expect(exception.toString(), contains('bad@email'));
    });

    test('EmailParseException includes details', () {
      final exception = EmailParseException('Invalid format');

      expect(exception.toString(), contains('Invalid format'));
    });

    test('RelayException includes details', () {
      final exception = RelayException('Connection failed');

      expect(exception.toString(), contains('Connection failed'));
    });

    test('NetworkRequiredException carries operation and details', () {
      final exception = NetworkRequiredException('nip05', 'DNS failure');

      expect(exception, isA<NostrMailException>());
      expect(exception.operation, 'nip05');
      expect(exception.toString(), contains('nip05'));
      expect(exception.toString(), contains('DNS failure'));
    });
  });
}
