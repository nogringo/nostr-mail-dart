import 'package:nostr_mail/src/client/cache_window.dart';
import 'package:nostr_mail/src/client/replay_queue.dart';
import 'package:test/test.dart';

void main() {
  group('ReplayQueue', () {
    late ReplayQueue queue;

    setUp(() => queue = ReplayQueue());

    test('owes nothing to start with', () {
      expect(queue.isPending, isFalse);
    });

    test('hands over what it was owed, once', () {
      queue.owe(const CacheWindow(100, 200));

      final window = queue.take();

      expect(window!.since, 100);
      expect(window.until, 200);
      expect(queue.isPending, isFalse);
    });

    test('merges what is owed while a round runs', () {
      queue.owe(const CacheWindow(100, 200));
      queue.owe(const CacheWindow(150, 300));

      final window = queue.take();

      expect(window!.since, 100);
      expect(window.until, 300);
    });

    test('owes the whole cache once anything asks for it', () {
      queue.owe(const CacheWindow(100, 200));
      queue.owe(null);

      expect(queue.isPending, isTrue);
      expect(queue.take(), isNull);
    });

    test('a window owed after a take is still a window, not the cache', () {
      queue.owe(null);
      queue.take();
      queue.owe(const CacheWindow(100, 200));

      expect(queue.take()!.since, 100);
    });

    // A round that throws, on a cancelled signer request, has to give its
    // ground back: no page will ask for that period a second time.
    test('keeps the ground of a round that gave it back', () {
      queue.owe(const CacheWindow(100, 200));
      final window = queue.take();

      queue.owe(window);

      expect(queue.isPending, isTrue);
      expect(queue.take()!.since, 100);
    });

    test('a page landing during a failed round is not lost either', () {
      queue.owe(const CacheWindow(100, 200));
      final running = queue.take();

      queue.owe(const CacheWindow(300, 400));
      queue.owe(running);

      final window = queue.take();

      expect(window!.since, 100);
      expect(window.until, 400);
    });
  });
}
