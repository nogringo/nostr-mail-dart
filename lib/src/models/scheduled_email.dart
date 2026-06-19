import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:ndk/entities.dart';
import 'package:nostr_event_scheduler/nostr_event_scheduler.dart' as scheduler;

import '../constants.dart';

/// Default Scheduler DVM used for delayed email delivery.
class SchedulerDvmConfig {
  /// Public key of the Scheduler DVM.
  final String pubkey;

  /// Read relays where the DVM receives scheduling requests.
  final List<String> readRelays;

  const SchedulerDvmConfig({required this.pubkey, this.readRelays = const []});
}

/// A scheduled email reconstructed from the private scheduler package context.
class ScheduledEmail {
  final String id;
  final DateTime scheduledAt;
  final String subject;
  final String? from;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final bool isPublic;
  final bool keepCopy;
  final Nip01Event? mailEvent;
  final List<String> requestEventIds;
  final Map<String, String> jobStatuses;

  const ScheduledEmail({
    required this.id,
    required this.scheduledAt,
    required this.subject,
    this.from,
    this.to = const [],
    this.cc = const [],
    this.bcc = const [],
    this.isPublic = false,
    this.keepCopy = true,
    this.mailEvent,
    this.requestEventIds = const [],
    this.jobStatuses = const {},
  });

  factory ScheduledEmail.fromScheduledItem(scheduler.ScheduledItem item) {
    final scheduled = tryFromScheduledItem(item);
    if (scheduled == null) {
      throw const FormatException('Scheduled item is not a nostr_mail email');
    }
    return scheduled;
  }

  static ScheduledEmail? tryFromScheduledItem(scheduler.ScheduledItem item) {
    final package = item.package;
    if (package == null) {
      return null;
    }

    final mailEvent = _decodeMailEvent(package.content);
    if (mailEvent == null) return null;

    final message = _decodeMime(mailEvent);
    final jobs = package.jobs;
    final firstScheduleAt = jobs.isEmpty ? null : jobs.first.scheduleAt;
    final senderPubkey = mailEvent.pubKey;
    return ScheduledEmail(
      id: package.packageId,
      scheduledAt: DateTime.fromMillisecondsSinceEpoch(
        (firstScheduleAt ?? mailEvent.createdAt) * 1000,
      ),
      subject: message?.decodeSubject() ?? '',
      from: message?.from?.map((a) => a.encode()).join(', '),
      to: message?.to?.map((a) => a.encode()).toList() ?? const [],
      cc: message?.cc?.map((a) => a.encode()).toList() ?? const [],
      bcc: message?.bcc?.map((a) => a.encode()).toList() ?? const [],
      isPublic: jobs.any((job) => job.targetEvent.kind == emailKind),
      keepCopy: jobs.any(
        (job) =>
            job.targetEvent.kind == giftWrapKind &&
            job.targetEvent.getFirstTag('p') == senderPubkey,
      ),
      mailEvent: mailEvent,
      requestEventIds: package.requestEventIds,
      jobStatuses: {for (final job in jobs) job.jobId: job.status.name},
    );
  }

  static Nip01Event? _decodeMailEvent(String content) {
    try {
      final decoded = jsonDecode(content) as Map<String, dynamic>;
      final event = Nip01EventModel.fromJson(decoded);
      return event.kind == emailKind ? event : null;
    } catch (_) {
      return null;
    }
  }

  static MimeMessage? _decodeMime(Nip01Event? event) {
    if (event == null || event.content.isEmpty) return null;
    try {
      return MimeMessage.parseFromText(event.content);
    } catch (_) {
      return null;
    }
  }
}

/// Status update for one Scheduler DVM job backing a scheduled email.
class ScheduledEmailStatusUpdate {
  final String jobId;
  final String status;
  final String? message;
  final DateTime receivedAt;

  const ScheduledEmailStatusUpdate({
    required this.jobId,
    required this.status,
    this.message,
    required this.receivedAt,
  });

  factory ScheduledEmailStatusUpdate.fromScheduler(
    scheduler.StatusUpdate update,
  ) {
    return ScheduledEmailStatusUpdate(
      jobId: update.jobId,
      status: update.status.name,
      message: update.message,
      receivedAt: update.receivedAt,
    );
  }
}

String scheduledEmailPackageContent(Nip01Event mailEvent) =>
    Nip01EventModel.fromEntity(mailEvent).toJsonString();
