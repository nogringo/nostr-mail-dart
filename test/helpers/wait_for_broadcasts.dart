import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';

/// Waits until [queue] holds no pending broadcast.
///
/// An SDK call that hands the queue a relay set to resolve returns before the
/// event reaches a relay: the lookup and the push both happen on the worker.
/// Reading the event back from a relay has to wait for that.
Future<void> waitForBroadcasts(
  OfflineBroadcast queue, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final deadline = DateTime.now().add(timeout);
  while (DateTime.now().isBefore(deadline)) {
    final all = await queue.listAll();
    if (all.every((b) => b.status != BroadcastStatus.pending)) return;
    await Future.delayed(const Duration(milliseconds: 50));
  }
  final pending = (await queue.listAll())
      .where((b) => b.status == BroadcastStatus.pending)
      .map((b) => '${b.id}: ${b.resolutionError ?? b.lastErrors}')
      .join('\n');
  throw StateError('broadcasts still pending after $timeout:\n$pending');
}
