/// Aggregate delivery status of a [ScheduledEmail], derived from its DVM jobs.
enum ScheduledEmailStatus {
  /// Requests broadcast, no DVM feedback yet.
  pending,

  /// The DVM accepted and queued every job.
  scheduled,

  /// Every job was published to its relays by the DVM.
  published,

  /// At least one job failed (relays unreachable or rejected).
  failed,

  /// Every job was cancelled.
  cancelled,

  /// At least one job request was rejected as invalid.
  error,
}

/// An email queued for future delivery through a Scheduler DVM.
///
/// Backed by a scheduled package (one DVM job per outgoing event). This is not a
/// local Sent copy: once the DVM publishes at [scheduleAt], the email lands in
/// Sent through the normal gift-wrap sync.
class ScheduledEmail {
  /// Id of the scheduled package. Pass it to cancel the schedule.
  final String packageId;

  /// When the DVM should send the email.
  final DateTime scheduleAt;

  final String? from;
  final List<String> to;
  final List<String> cc;
  final List<String> bcc;
  final String subject;

  /// Short one-line preview of the body.
  final String bodyPreview;

  final bool isPublic;
  final List<String> attachmentNames;

  /// Aggregate status across the package's DVM jobs.
  final ScheduledEmailStatus status;

  /// When the schedule was created locally.
  final DateTime createdAt;

  ScheduledEmail({
    required this.packageId,
    required this.scheduleAt,
    required this.from,
    required this.to,
    required this.cc,
    required this.bcc,
    required this.subject,
    required this.bodyPreview,
    required this.isPublic,
    required this.attachmentNames,
    required this.status,
    required this.createdAt,
  });

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is ScheduledEmail && packageId == other.packageId;

  @override
  int get hashCode => packageId.hashCode;
}
