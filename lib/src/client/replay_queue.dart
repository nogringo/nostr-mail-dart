import 'cache_window.dart';

/// The ground a replay round still owes the local stores.
///
/// Holding it here rather than in a pair of fields is what makes a failed
/// round harmless: it gives its ground back with [owe], and the next round
/// covers it. A page that landed while it ran is already in there, so the two
/// merge instead of one replacing the other.
class ReplayQueue {
  var _pending = false;
  CacheWindow? _window;

  /// Whether anything is owed. A null window still counts.
  bool get isPending => _pending;

  /// Adds [window] to what is owed; null owes the whole cache.
  void owe(CacheWindow? window) {
    _window = _pending ? CacheWindow.union(_window, window) : window;
    _pending = true;
  }

  /// Hands over what is owed and clears it. Null covers the whole cache.
  CacheWindow? take() {
    final window = _window;
    _pending = false;
    _window = null;
    return window;
  }
}
