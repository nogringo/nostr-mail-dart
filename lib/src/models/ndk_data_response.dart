import 'package:rxdart/rxdart.dart';

// Local copy of the local-first reads ADR (relaystr/ndk#702), until ndk ships it.

enum DataOrigin { cache, relays }

class NdkValue<T> {
  final T? value;
  final DataOrigin origin;

  const NdkValue(this.value, this.origin);
}

class NdkDataResponse<T> {
  final BehaviorSubject<NdkValue<T>> _subject;

  NdkDataResponse(this._subject);

  /// Emits a `cache` value first, then every newer `relays` value as it
  /// arrives. Closes after EOSE or timeout.
  Stream<NdkValue<T>> get stream => _subject.stream;

  /// The last emitted value, relay-confirmed unless the read concludes on cache.
  Future<NdkValue<T>> get future => _subject.stream.last;
}
