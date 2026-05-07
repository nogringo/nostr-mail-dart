import 'dart:async';

import '../models/mail_event.dart';

/// Internal broadcast bus for [MailEvent]s shared across client managers.
class EventBus {
  StreamController<MailEvent>? _controller;
  Stream<MailEvent>? _broadcastStream;

  /// Returns the shared broadcast stream, creating it on first use.
  Stream<MailEvent> get stream {
    _controller ??= StreamController<MailEvent>.broadcast();
    _broadcastStream ??= _controller!.stream;
    return _broadcastStream!;
  }

  /// Emit a new event to all listeners.
  void emit(MailEvent event) => _controller?.add(event);

  /// True if the bus is currently active.
  bool get isActive => _controller != null && !_controller!.isClosed;

  /// Close the bus. After this, the next call to [stream] creates a fresh one.
  void close() {
    _controller?.close();
    _controller = null;
    _broadcastStream = null;
  }
}
