import 'package:sync_engine_shim_for_ndk/sync_engine_shim_for_ndk.dart';

/// The slice of the NDK cache a replay round has to cover, in seconds.
class CacheWindow {
  final int since;
  final int until;

  const CacheWindow(this.since, this.until);

  /// The period [progress] just closed.
  ///
  /// Its old end is pulled back a second: a page stops one second above its
  /// oldest event, because a single second cannot be paginated any finer, but
  /// that second's events are already in the cache.
  factory CacheWindow.of(SyncProgress progress) => CacheWindow(
    progress.from.millisecondsSinceEpoch ~/ 1000 - 1,
    progress.to.millisecondsSinceEpoch ~/ 1000,
  );

  /// The window holding both, or null (the whole cache) if either is null.
  ///
  /// Two windows of one walk are adjacent, so spanning them wastes nothing;
  /// two that are far apart are still cheaper to cover in one round than to
  /// track separately.
  static CacheWindow? union(CacheWindow? a, CacheWindow? b) =>
      a == null || b == null
      ? null
      : CacheWindow(
          a.since < b.since ? a.since : b.since,
          a.until > b.until ? a.until : b.until,
        );
}
