import 'package:ndk/ndk.dart';

/// Waits until [event] is no longer dated ahead of the clock.
///
/// A version or a verdict following another in the same second is dated a
/// second later, and the sync engine never asks for the future.
Future<void> untilPast(Nip01Event event) => Future.delayed(
  DateTime.fromMillisecondsSinceEpoch(
    event.createdAt * 1000,
  ).difference(DateTime.now()),
);
