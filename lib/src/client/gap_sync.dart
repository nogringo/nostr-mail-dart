import 'package:ndk/ndk.dart';

/// Template method that fetches only the time-gap ranges not yet covered
/// by [Ndk.fetchedRanges].
///
/// Subclasses provide the Nostr [Filter], the fetch logic and the per-item
/// processing logic.
abstract class GapSync<T> {
  final Ndk ndkClient;
  final String pubkey;
  final List<String> relays;
  final int? since;
  final int until;

  GapSync(this.ndkClient, this.pubkey, this.relays, this.since, this.until);

  Filter buildFilter(String pubkey);
  Future<List<T>> fetch(Filter filter, List<String> relays);
  Future<void> process(T item);

  Future<void> execute() async {
    final baseFilter = buildFilter(pubkey);
    final existingRanges = await ndkClient.fetchedRanges.getForFilter(
      baseFilter,
    );

    if (existingRanges.isEmpty) {
      final filter = baseFilter.clone()
        ..since = since
        ..until = until;
      final items = await fetch(filter, relays);
      for (final item in items) {
        await process(item);
      }
      return;
    }

    final optimizedFilters = await ndkClient.fetchedRanges.getOptimizedFilters(
      filter: baseFilter,
      since: since ?? 0,
      until: until,
    );

    if (optimizedFilters.isEmpty) return;

    for (final gapFilter in optimizedFilters.values.expand((f) => f)) {
      final items = await fetch(gapFilter, relays);
      for (final item in items) {
        await process(item);
      }
    }
  }
}
