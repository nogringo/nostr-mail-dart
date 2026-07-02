import 'package:nostr_event_scheduler/nostr_event_scheduler.dart';
import 'package:nostr_mail/nostr_mail.dart';
import 'package:nostr_mail/src/client/schedule_manager.dart';
import 'package:test/test.dart';

void main() {
  group('ScheduleManager.aggregateStatus', () {
    test('no jobs -> pending', () {
      expect(
        ScheduleManager.aggregateStatus(const []),
        ScheduledEmailStatus.pending,
      );
    });

    test('all published -> published', () {
      expect(
        ScheduleManager.aggregateStatus([
          JobStatus.published,
          JobStatus.published,
        ]),
        ScheduledEmailStatus.published,
      );
    });

    test('error takes precedence over everything', () {
      expect(
        ScheduleManager.aggregateStatus([
          JobStatus.published,
          JobStatus.failed,
          JobStatus.error,
        ]),
        ScheduledEmailStatus.error,
      );
    });

    test('failed when any failed and no error', () {
      expect(
        ScheduleManager.aggregateStatus([
          JobStatus.published,
          JobStatus.failed,
        ]),
        ScheduledEmailStatus.failed,
      );
    });

    test('pending while any job is still pending', () {
      expect(
        ScheduleManager.aggregateStatus([
          JobStatus.scheduled,
          JobStatus.pending,
        ]),
        ScheduledEmailStatus.pending,
      );
    });

    test('all cancelled -> cancelled', () {
      expect(
        ScheduleManager.aggregateStatus([
          JobStatus.cancelled,
          JobStatus.cancelled,
        ]),
        ScheduledEmailStatus.cancelled,
      );
    });

    test('scheduled when queued and none pending', () {
      expect(
        ScheduleManager.aggregateStatus([
          JobStatus.scheduled,
          JobStatus.scheduled,
        ]),
        ScheduledEmailStatus.scheduled,
      );
    });
  });
}
