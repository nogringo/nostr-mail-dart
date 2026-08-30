import 'package:nostr_mail/src/utils/throttle.dart';
import 'package:test/test.dart';

void main() {
  group('forEachThrottled', () {
    test('never runs more than the limit at once', () async {
      var inFlight = 0;
      var peak = 0;

      await forEachThrottled(List.generate(20, (i) => i), 3, (_) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        inFlight--;
      });

      expect(peak, 3);
    });

    test('runs every item', () async {
      final handled = <int>[];

      await forEachThrottled(List.generate(20, (i) => i), 3, (item) async {
        await Future<void>.delayed(const Duration(milliseconds: 1));
        handled.add(item);
      });

      expect(handled, unorderedEquals(List.generate(20, (i) => i)));
    });

    test('starts one worker per item when there are fewer than the limit', () {
      var inFlight = 0;
      var peak = 0;

      final run = forEachThrottled([1, 2], 8, (_) async {
        inFlight++;
        if (inFlight > peak) peak = inFlight;
        await Future<void>.delayed(const Duration(milliseconds: 1));
        inFlight--;
      });

      expect(peak, 2);
      return run;
    });

    test('does nothing with no items', () async {
      await forEachThrottled(<int>[], 3, (_) async => fail('handled an item'));
    });

    test('stops at the first error and leaves the rest alone', () async {
      final started = <int>[];

      await expectLater(
        forEachThrottled(List.generate(10, (i) => i), 1, (item) async {
          started.add(item);
          if (item == 2) throw StateError('boom');
        }),
        throwsStateError,
      );

      expect(started, [0, 1, 2]);
    });
  });
}
