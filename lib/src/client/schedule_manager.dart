import 'dart:convert';

import 'package:enough_mail_plus/enough_mail.dart';
import 'package:nostr_event_scheduler/nostr_event_scheduler.dart';

import '../exceptions.dart';
import '../models/recipient.dart';
import '../models/scheduled_email.dart';
import '../utils/html_utils.dart';
import 'email_sender.dart';

/// Schedules emails for future delivery via a Scheduler DVM (kind:5905 requests
/// grouped in a kind:31234 package) and manages the resulting schedules.
///
/// One email maps to one package: one DVM job per outgoing event (a gift wrap
/// per recipient, the public event, bridge gift wraps, and the sender's own
/// gift wrap when keepCopy). The private display context (subject, recipients,
/// preview, schedule time) is stored NIP-44 encrypted in the package content.
class ScheduleManager {
  final EventScheduler _scheduler;
  final EmailSender _sender;
  final String? defaultDvm;
  final List<String>? dvmReadRelays;

  ScheduleManager(
    this._scheduler,
    this._sender, {
    this.defaultDvm,
    this.dvmReadRelays,
  });

  bool _listening = false;

  /// Start listening for DVM feedback and multi-device sync. Requires a
  /// logged-in account. Idempotent.
  Future<void> startListening() async {
    if (_listening) return;
    _listening = true;
    await _scheduler.startListening();
  }

  Future<void> stopListening() async {
    if (!_listening) return;
    _listening = false;
    await _scheduler.stopListening();
  }

  Future<void> dispose() => _scheduler.dispose();

  /// Compose an email from parts and schedule it at [at]. See [scheduleMime].
  Future<ScheduledEmail> scheduleEmail({
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    required String subject,
    required String body,
    MailAddress? from,
    String? htmlBody,
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    required DateTime at,
    String? dvmPubkey,
  }) async {
    final message = await _sender.composeMime(
      to: to,
      cc: cc,
      bcc: bcc,
      subject: subject,
      body: body,
      from: from,
      htmlBody: htmlBody,
    );
    return scheduleMime(
      message,
      to: to,
      cc: cc,
      bcc: bcc,
      keepCopy: keepCopy,
      signRumor: signRumor,
      isPublic: isPublic,
      at: at,
      dvmPubkey: dvmPubkey,
    );
  }

  /// Schedule a pre-built [message] to be sent at [at].
  ///
  /// Mirrors `EmailSender.sendMime` routing: [to]/[cc]/[bcc] drive delivery and
  /// [at] dates the rumors. The DVM that runs the jobs is [dvmPubkey] or the
  /// configured default; throws when neither is set.
  Future<ScheduledEmail> scheduleMime(
    MimeMessage message, {
    required List<Recipient> to,
    List<Recipient> cc = const [],
    List<Recipient> bcc = const [],
    bool keepCopy = true,
    bool signRumor = false,
    bool isPublic = false,
    String? mailFrom,
    required DateTime at,
    String? dvmPubkey,
  }) async {
    final dvm = dvmPubkey ?? defaultDvm;
    if (dvm == null) {
      throw NostrMailException('No scheduler DVM configured');
    }

    final outgoing = await _sender.buildOutgoing(
      message,
      to: to,
      cc: cc,
      bcc: bcc,
      keepCopy: keepCopy,
      signRumor: signRumor,
      isPublic: isPublic,
      mailFrom: mailFrom,
      rumorCreatedAt: at.millisecondsSinceEpoch ~/ 1000,
    );
    if (outgoing.isEmpty) {
      throw NostrMailException('No events to schedule');
    }

    final items = outgoing
        .map(
          (e) => SchedulePackageItem(
            event: e.event,
            dvmPubkey: dvm,
            at: at,
            relays: e.relays,
            dvmReadRelays: dvmReadRelays,
          ),
        )
        .toList();

    final content = _encodeContent(
      message: message,
      to: to,
      cc: cc,
      bcc: bcc,
      isPublic: isPublic,
      at: at,
    );

    final package = await _scheduler.schedulePackage(items, content: content);
    return _toScheduledEmail(package);
  }

  /// All scheduled emails, newest first.
  Future<List<ScheduledEmail>> list() async {
    final packages = await _scheduler.listPackages();
    return _sortNewest(packages.map(_tryMap));
  }

  /// Reactive [list]: re-emits whenever a schedule is added, cancelled, or its
  /// DVM feedback changes.
  Stream<List<ScheduledEmail>> watch() {
    return _scheduler.schedulesStream.map(
      (items) => _sortNewest(
        items
            .where((i) => i.type == ScheduledItemType.package)
            .map((i) => _tryMap(i.package)),
      ),
    );
  }

  /// Cancel a scheduled email by its [packageId]: deletes the package and its
  /// DVM jobs (NIP-09), so the DVM never publishes.
  Future<void> cancel(String packageId) => _scheduler.cancelPackage(packageId);

  // ── Mapping ────────────────────────────────────────────────────────────────

  List<ScheduledEmail> _sortNewest(Iterable<ScheduledEmail?> emails) {
    final list = emails.whereType<ScheduledEmail>().toList();
    list.sort((a, b) => b.createdAt.compareTo(a.createdAt));
    return list;
  }

  /// Map a package to a [ScheduledEmail], or null if its content is not ours.
  ScheduledEmail? _tryMap(ScheduledPackage? package) {
    if (package == null) return null;
    try {
      return _toScheduledEmail(package);
    } catch (_) {
      return null;
    }
  }

  ScheduledEmail _toScheduledEmail(ScheduledPackage package) {
    final data = jsonDecode(package.content) as Map<String, dynamic>;
    List<String> strList(Object? v) =>
        (v as List<dynamic>?)?.map((e) => e as String).toList() ?? const [];
    return ScheduledEmail(
      packageId: package.packageId,
      scheduleAt: DateTime.fromMillisecondsSinceEpoch(
        (data['scheduleAt'] as int) * 1000,
      ),
      from: data['from'] as String?,
      to: strList(data['to']),
      cc: strList(data['cc']),
      bcc: strList(data['bcc']),
      subject: data['subject'] as String? ?? '',
      bodyPreview: data['bodyPreview'] as String? ?? '',
      isPublic: data['isPublic'] as bool? ?? false,
      attachmentNames: strList(data['attachmentNames']),
      status: aggregateStatus(package.jobs.map((j) => j.status)),
      createdAt: DateTime.fromMillisecondsSinceEpoch(package.createdAt * 1000),
    );
  }

  String _encodeContent({
    required MimeMessage message,
    required List<Recipient> to,
    required List<Recipient> cc,
    required List<Recipient> bcc,
    required bool isPublic,
    required DateTime at,
  }) {
    List<String> addrs(List<Recipient> rs) =>
        rs.map((r) => r.mailAddress.email).toList();
    return jsonEncode({
      'v': 1,
      'scheduleAt': at.millisecondsSinceEpoch ~/ 1000,
      'from': message.fromEmail,
      'to': addrs(to),
      'cc': addrs(cc),
      'bcc': addrs(bcc),
      'subject': message.decodeSubject() ?? '',
      'bodyPreview': _bodyPreview(message),
      'isPublic': isPublic,
      'attachmentNames': _attachmentNames(message),
    });
  }

  static String _bodyPreview(MimeMessage message, {int max = 140}) {
    var text = message.decodeTextPlainPart() ?? '';
    if (text.isEmpty) {
      text = stripHtmlTags(message.decodeTextHtmlPart() ?? '');
    }
    text = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    return text.length > max ? '${text.substring(0, max)}...' : text;
  }

  static List<String> _attachmentNames(MimeMessage message) {
    final names = <String>[];
    void walk(MimePart part) {
      final children = part.parts;
      if (children != null && children.isNotEmpty) {
        for (final child in children) {
          walk(child);
        }
        return;
      }
      final disposition = part.getHeaderContentDisposition()?.disposition;
      final filename = part.decodeFileName();
      final isAttachment =
          disposition == ContentDisposition.attachment ||
          (filename != null && filename.isNotEmpty);
      if (isAttachment && filename != null && filename.isNotEmpty) {
        names.add(filename);
      }
    }

    walk(message);
    return names;
  }

  /// Collapse per-job [statuses] into one [ScheduledEmailStatus].
  static ScheduledEmailStatus aggregateStatus(Iterable<JobStatus> statuses) {
    final list = statuses.toList();
    if (list.isEmpty) return ScheduledEmailStatus.pending;
    bool any(JobStatus s) => list.contains(s);
    bool all(JobStatus s) => list.every((e) => e == s);
    if (any(JobStatus.error)) return ScheduledEmailStatus.error;
    if (any(JobStatus.failed)) return ScheduledEmailStatus.failed;
    if (all(JobStatus.published)) return ScheduledEmailStatus.published;
    if (all(JobStatus.cancelled)) return ScheduledEmailStatus.cancelled;
    if (any(JobStatus.pending)) return ScheduledEmailStatus.pending;
    return ScheduledEmailStatus.scheduled;
  }
}
