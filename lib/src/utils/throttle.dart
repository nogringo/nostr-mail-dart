/// Runs [handle] over [items], at most [limit] at a time.
///
/// The first error stops the run: what is already in flight finishes, nothing
/// further starts, and the error is rethrown.
Future<void> forEachThrottled<T>(
  List<T> items,
  int limit,
  Future<void> Function(T item) handle,
) async {
  assert(limit > 0, 'limit must be > 0');

  var next = 0;
  var stopped = false;

  Future<void> worker() async {
    while (next < items.length && !stopped) {
      final item = items[next++];
      try {
        await handle(item);
      } catch (_) {
        stopped = true;
        rethrow;
      }
    }
  }

  final workers = items.length < limit ? items.length : limit;
  await Future.wait(List.generate(workers, (_) => worker()));
}
