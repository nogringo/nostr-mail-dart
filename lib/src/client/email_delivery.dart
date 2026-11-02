import 'package:broadcast_queue_shim_for_ndk/broadcast_queue_shim_for_ndk.dart';
import 'package:ndk/ndk.dart';

/// A signed event ready to publish, paired with its target relays.
class OutgoingEvent {
  final Nip01Event event;
  final List<String> relays;

  /// The seal inside, when [event] is a gift wrap this device built.
  final Nip01Event? seal;
  OutgoingEvent(this.event, this.relays, {this.seal});
}

/// Wraps a rumor into a NIP-59 gift wrap for [recipientPubkey], bound for the
/// [relays] it receives on.
typedef GiftWrapBuilder =
    Future<OutgoingEvent> Function(
      Nip01Event rumor,
      String recipientPubkey,
      List<String> relays,
    );

/// Hook invoked after an event and its destination relays are fully resolved,
/// immediately before the event is persisted to the broadcast queue.
typedef BeforePublish =
    Future<void> Function(Nip01Event event, List<String> relays);

/// Hook invoked with a freshly built gift wrap, before it is delivered.
typedef OnGiftWrapBuilt = Future<void> Function(OutgoingEvent wrap);

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

  /// Whether a gift wrap can leave before its recipient's relays are known.
  bool get looksUpRelays;

  Future<void> deliverEvent(Nip01Event event, List<String> relays);

  /// [relays] is null when no relay answered the lookup, which only a
  /// [looksUpRelays] delivery accepts.
  Future<OutgoingEvent> deliverGiftWrap(
    Nip01Event rumor,
    String recipientPubkey,
    List<String>? relays, {
    OnGiftWrapBuilt? onBuilt,
  });
}

/// Broadcasts each built event immediately through the offline queue.
///
/// Every entry is attributed to [senderPubkey] so the queue can be wiped per
/// account on logout. Gift wraps carry an ephemeral event pubkey, so the
/// sending account is the only usable attribution.
///
/// The relays are resolved here and queued as a `UrlSet.explicit`: a send
/// reports the exact relay list it targets through [BeforePublish], and the
/// same list goes in the `public-ref` tag of a public email. A gift wrap whose
/// relays could not be looked up, offline for one, is queued with
/// [receivingRelays] instead, for the queue to resolve once a relay answers,
/// and reports no relay.
class BroadcastDelivery implements Delivery {
  final OfflineBroadcast _queue;
  final GiftWrapBuilder _buildGiftWrap;
  final BeforePublish? _beforePublish;
  final String senderPubkey;
  final UrlSet Function(String pubkey) receivingRelays;
  final int _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  BroadcastDelivery(
    this._queue,
    this._buildGiftWrap,
    this._beforePublish, {
    required this.senderPubkey,
    required this.receivingRelays,
  });

  @override
  int get rumorCreatedAt => _now;

  @override
  bool get saveSelfCopy => true;

  @override
  bool get looksUpRelays => true;

  @override
  Future<void> deliverEvent(Nip01Event event, List<String> relays) async {
    await _beforePublish?.call(event, relays);
    await _queue.broadcast(
      event,
      relaySet: UrlSet.explicit(relays),
      pubkey: senderPubkey,
    );
  }

  @override
  Future<OutgoingEvent> deliverGiftWrap(
    Nip01Event rumor,
    String recipientPubkey,
    List<String>? relays, {
    OnGiftWrapBuilt? onBuilt,
  }) async {
    final out = await _buildGiftWrap(
      rumor,
      recipientPubkey,
      relays ?? const [],
    );
    await onBuilt?.call(out);
    await _beforePublish?.call(out.event, out.relays);
    await _queue.broadcast(
      out.event,
      relaySet: relays == null
          ? receivingRelays(recipientPubkey)
          : UrlSet.explicit(out.relays),
      pubkey: senderPubkey,
    );
    return out;
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

  /// The scheduler publishes to the relays it is handed.
  @override
  bool get looksUpRelays => false;

  @override
  Future<void> deliverEvent(Nip01Event event, List<String> relays) async {
    items.add(OutgoingEvent(event, relays));
  }

  @override
  Future<OutgoingEvent> deliverGiftWrap(
    Nip01Event rumor,
    String recipientPubkey,
    List<String>? relays, {
    OnGiftWrapBuilt? onBuilt,
  }) async {
    final out = await _buildGiftWrap(rumor, recipientPubkey, relays!);
    await onBuilt?.call(out);
    items.add(out);
    return out;
  }
}
