import 'package:ndk/entities.dart' show Nip01Event;
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

    test('sending once some jobs are published and others are not', () {
      expect(
        ScheduleManager.aggregateStatus([
          JobStatus.published,
          JobStatus.scheduled,
        ]),
        ScheduledEmailStatus.sending,
      );
      expect(
        ScheduleManager.aggregateStatus([
          JobStatus.published,
          JobStatus.pending,
        ]),
        ScheduledEmailStatus.sending,
      );
    });
  });

  group('ScheduleManager.statusMessage', () {
    ScheduledJob job(JobStatus status, String? message) {
      return ScheduledJob(
        pubkey: 'client',
        jobId: 'job',
        scheduleAt: 0,
        targetEvent: Nip01Event(
          pubKey: 'client',
          kind: 1,
          tags: [],
          content: '',
        ),
        targetRelays: const [],
        requests: [
          ScheduledJobRequest(
            dvmPubkey: 'dvm',
            requestEventId: 'request',
            status: status,
            lastMessage: message,
            updatedAt: 0,
          ),
        ],
        createdAt: 0,
        updatedAt: 0,
      );
    }

    test('picks the message of a job matching the status', () {
      expect(
        ScheduleManager.statusMessage([
          job(JobStatus.published, 'done'),
          job(JobStatus.failed, ' '),
          job(JobStatus.failed, 'relays unreachable'),
        ], ScheduledEmailStatus.failed),
        'relays unreachable',
      );
    });

    test('is null when no matching job carries a message', () {
      expect(
        ScheduleManager.statusMessage([
          job(JobStatus.failed, null),
        ], ScheduledEmailStatus.failed),
        isNull,
      );
      expect(
        ScheduleManager.statusMessage([
          job(JobStatus.published, 'done'),
        ], ScheduledEmailStatus.sending),
        isNull,
      );
    });
  });
}
