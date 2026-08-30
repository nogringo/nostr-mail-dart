import 'package:nostr_mail/src/client/cache_window.dart';
import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';
import 'package:test/test.dart';

void main() {
  SyncProgress page({required int from, required int to}) => SyncProgress(
    relayUrl: 'wss://relay.example',
    filterFingerprint: 'fingerprint',
    from: DateTime.fromMillisecondsSinceEpoch(from * 1000, isUtc: true),
    to: DateTime.fromMillisecondsSinceEpoch(to * 1000, isUtc: true),
    eventCount: 1,
  );

  group('CacheWindow.of', () {
    test('covers the period the page closed, in seconds', () {
      final window = CacheWindow.of(page(from: 1000, to: 2000));

      expect(window.until, 2000);
    });

    // A page stops one second above its oldest event, so taking its old bound
    // at face value would skip that event on every page of a walk.
    test('reaches one second below the page, where its oldest event sits', () {
      final window = CacheWindow.of(page(from: 1000, to: 2000));

      expect(window.since, 999);
    });
  });

  group('CacheWindow.union', () {
    test('holds both windows', () {
      final union = CacheWindow.union(
        const CacheWindow(100, 200),
        const CacheWindow(150, 300),
      );

      expect(union!.since, 100);
      expect(union.until, 300);
    });

    test('spans the gap between two windows that do not touch', () {
      final union = CacheWindow.union(
        const CacheWindow(100, 200),
        const CacheWindow(500, 600),
      );

      expect(union!.since, 100);
      expect(union.until, 600);
    });

    test('is the whole cache when either side is', () {
      expect(CacheWindow.union(const CacheWindow(100, 200), null), isNull);
      expect(CacheWindow.union(null, const CacheWindow(100, 200)), isNull);
      expect(CacheWindow.union(null, null), isNull);
    });
  });
}
