import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:ndk/ndk.dart';

/// A signed event ready to publish, paired with its target relays.
class OutgoingEvent {
  final Nip01Event event;
  final List<String> relays;
  OutgoingEvent(this.event, this.relays);
}

/// Wraps a rumor into a NIP-59 gift wrap for [recipientPubkey], returning the
/// gift wrap and the relays it should go to.
typedef GiftWrapBuilder =
    Future<OutgoingEvent> Function(Nip01Event rumor, String recipientPubkey);

/// Hook invoked after an event and its destination relays are fully resolved,
/// immediately before the event is persisted to the broadcast queue.
typedef BeforePublish =
    Future<void> Function(Nip01Event event, List<String> relays);

/// Strategy for where the events built during a send go: broadcast now, or
/// collected for later scheduling. Lets the sender share one build path for
/// immediate and scheduled sends.
abstract class Delivery {
  /// Epoch seconds to stamp on the rumors. ndk dates the seal and gift wrap in
  /// the 2 days before the rumor's created_at, so a scheduled send just passes
  /// the schedule time here to date the whole envelope correctly.
  int get rumorCreatedAt;

  /// Whether to persist the sender's local Sent copy during the send.
  bool get saveSelfCopy;

  Future<void> deliverEvent(Nip01Event event, List<String> relays);
  Future<void> deliverGiftWrap(Nip01Event rumor, String recipientPubkey);
}

/// Broadcasts each built event immediately through the offline queue.
class BroadcastDelivery implements Delivery {
  final OfflineBroadcast _queue;
  final GiftWrapBuilder _buildGiftWrap;
  final BeforePublish? _beforePublish;
  final int _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  BroadcastDelivery(this._queue, this._buildGiftWrap, this._beforePublish);

  @override
  int get rumorCreatedAt => _now;

  @override
  bool get saveSelfCopy => true;

  @override
  Future<void> deliverEvent(Nip01Event event, List<String> relays) async {
    await _beforePublish?.call(event, relays);
    await _queue.broadcast(event, relays: relays);
  }

  @override
  Future<void> deliverGiftWrap(Nip01Event rumor, String recipientPubkey) async {
    final out = await _buildGiftWrap(rumor, recipientPubkey);
    await _beforePublish?.call(out.event, out.relays);
    await _queue.broadcast(out.event, relays: out.relays);
  }
}

/// Collects the built events (dated at [_at]) instead of broadcasting, so they
/// can be handed to a scheduler that publishes them later.
class ScheduleDelivery implements Delivery {
  final int _at;
  final GiftWrapBuilder _buildGiftWrap;
  final List<OutgoingEvent> items = [];
  ScheduleDelivery(this._at, this._buildGiftWrap);

  @override
  int get rumorCreatedAt => _at;

  @override
  bool get saveSelfCopy => false;

  @override
  Future<void> deliverEvent(Nip01Event event, List<String> relays) async {
    items.add(OutgoingEvent(event, relays));
  }

  @override
  Future<void> deliverGiftWrap(Nip01Event rumor, String recipientPubkey) async {
    items.add(await _buildGiftWrap(rumor, recipientPubkey));
  }
}
