import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/local_time.dart';
import 'package:lynai/models/scheduled_task.dart';

ScheduledTask task({
  ScheduledTaskRepeat repeat = ScheduledTaskRepeat.daily,
  LocalTime? time,
  List<int> daysOfWeek = const [],
  String? id = 'st_1',
}) {
  final effectiveTime = time ?? LocalTime(23, 0);
  final timestamp = DateTime(2026, 2, 23, 12);
  return ScheduledTask(
    id: id!,
    name: '每日总结',
    pluginId: 'daily-diary',
    repeat: repeat,
    time: effectiveTime,
    daysOfWeek: daysOfWeek,
    scriptKind: ScheduledTaskScriptKind.inline,
    script: 'function run(ctx) return {ok=true} end',
    source: ScheduledTaskSource.user,
    createdAt: timestamp,
    updatedAt: timestamp,
  );
}

void main() {
  group('ScheduledTask validation', () {
    test('weekly requires days and validates 1-7', () {
      expect(
        () => task(repeat: ScheduledTaskRepeat.weekly, daysOfWeek: const []),
        throwsArgumentError,
      );
      expect(
        () => task(repeat: ScheduledTaskRepeat.weekly, daysOfWeek: const [0]),
        throwsArgumentError,
      );
      expect(
        task(repeat: ScheduledTaskRepeat.weekly, daysOfWeek: const [1, 5]),
        isA<ScheduledTask>(),
      );
    });

    test('inline script has size limit and file scripts do not', () {
      expect(
        () => task().copyWith(
          script: 'x' * (ScheduledTask.maxInlineScriptChars + 1),
        ),
        throwsArgumentError,
      );
      final fileTask = task().copyWith(
        scriptKind: ScheduledTaskScriptKind.file,
        script: 'x' * (ScheduledTask.maxInlineScriptChars + 1),
      );
      expect(
        fileTask.script.length,
        greaterThan(ScheduledTask.maxInlineScriptChars),
      );
    });
  });

  group('occurrence calculation', () {
    test('daily before time schedules today', () {
      final item = task(time: LocalTime(23, 0));
      expect(
        item.nextOccurrenceOnOrAfter(DateTime(2026, 2, 23, 10)),
        DateTime(2026, 2, 23, 23),
      );
    });

    test('daily after time schedules tomorrow', () {
      final item = task(time: LocalTime(23, 0));
      expect(
        item.nextOccurrenceOnOrAfter(DateTime(2026, 2, 23, 23, 30)),
        DateTime(2026, 2, 24, 23),
      );
    });

    test('weekly finds next matching weekday', () {
      final item = task(
        repeat: ScheduledTaskRepeat.weekly,
        time: LocalTime(9, 0),
        daysOfWeek: const [1, 5],
      );
      // 2026-02-23 is Monday.
      expect(
        item.nextOccurrenceOnOrAfter(DateTime(2026, 2, 23, 8)),
        DateTime(2026, 2, 23, 9),
      );
      expect(
        item.nextOccurrenceOnOrAfter(DateTime(2026, 2, 24, 8)),
        DateTime(2026, 2, 27, 9),
      );
    });

    test('nextOccurrenceAfter uses the old occurrence as base', () {
      final item = task(time: LocalTime(23, 0));
      final missed = DateTime(2026, 2, 23, 23);
      expect(item.nextOccurrenceAfter(missed), DateTime(2026, 2, 24, 23));
      expect(
        item.nextOccurrenceAfter(DateTime(2026, 2, 23, 23)),
        DateTime(2026, 2, 24, 23),
      );
    });
  });

  group('run state transitions', () {
    test('success advances to next occurrence and clears failures', () {
      final item = task().copyWith(
        nextRunAt: DateTime(2026, 2, 23, 23),
        consecutiveFailures: 2,
      );
      final completed = item.completedAt(DateTime(2026, 2, 24, 0, 30));
      expect(completed.nextRunAt, DateTime(2026, 2, 24, 23));
      expect(completed.lastRunAt, DateTime(2026, 2, 24, 0, 30));
      expect(completed.lastStatus, ScheduledTaskRunStatus.success);
      expect(completed.consecutiveFailures, 0);
    });

    test('failure keeps occurrence and disables after limit', () {
      final item = task().copyWith(nextRunAt: DateTime(2026, 2, 23, 23));
      var failed = item.failedAt(DateTime(2026, 2, 23, 23, 1), 'boom');
      expect(failed.nextRunAt, DateTime(2026, 2, 23, 23));
      expect(failed.lastStatus, ScheduledTaskRunStatus.failed);
      expect(failed.enabled, isTrue);

      failed = failed.failedAt(DateTime(2026, 2, 23, 23, 2), 'boom');
      final disabled = failed.failedAt(DateTime(2026, 2, 23, 23, 3), 'boom');
      expect(disabled.enabled, isFalse);
    });

    test('manual success without occurrence advance', () {
      final item = task().copyWith(nextRunAt: DateTime(2026, 2, 23, 23));
      final manual = item.copyWith(
        lastAttemptAt: DateTime(2026, 2, 23, 22),
        lastRunAt: DateTime(2026, 2, 23, 22),
        lastStatus: ScheduledTaskRunStatus.success,
      );
      expect(manual.nextRunAt, DateTime(2026, 2, 23, 23));
    });

    test('skipped advances to the next occurrence', () {
      final item = task().copyWith(nextRunAt: DateTime(2026, 2, 23, 23));
      final skipped = item.skippedAt(DateTime(2026, 2, 23, 23, 5), 'missing');
      expect(skipped.nextRunAt, DateTime(2026, 2, 24, 23));
    });

    test('cancelled keeps occurrence for later catch-up', () {
      final item = task().copyWith(nextRunAt: DateTime(2026, 2, 23, 23));
      final cancelled = item.cancelledAt(DateTime(2026, 2, 23, 23, 5), 'stop');
      expect(cancelled.nextRunAt, DateTime(2026, 2, 23, 23));
      expect(cancelled.isDueAt(DateTime(2026, 2, 24, 7)), isTrue);
    });
  });

  test('run history keeps newest first and caps at max entries', () {
    var item = task().copyWith(nextRunAt: DateTime(2026, 2, 23, 23));
    for (var i = 0; i < ScheduledTask.maxRunHistory + 3; i++) {
      item = item
          .copyWith(nextRunAt: DateTime(2026, 2, 23, 23))
          .completedAt(DateTime(2026, 2, 23, 23, i));
    }
    expect(item.runHistory, hasLength(ScheduledTask.maxRunHistory));
    expect(item.runHistory.first.at.minute, ScheduledTask.maxRunHistory + 2);
    expect(item.runHistory.last.at.minute, 3);
  });

  test('failed runs are recorded in history', () {
    final item = task()
        .copyWith(nextRunAt: DateTime(2026, 2, 23, 23))
        .failedAt(DateTime(2026, 2, 23, 23), 'boom');
    expect(item.runHistory.single.status, ScheduledTaskRunStatus.failed);
    expect(item.runHistory.single.error, 'boom');
  });

  test('json roundtrip preserves schedule and state', () {
    final item =
        task(
          repeat: ScheduledTaskRepeat.weekly,
          daysOfWeek: const [1, 3, 5],
        ).copyWith(
          nextRunAt: DateTime(2026, 2, 23, 23),
          lastAttemptAt: DateTime(2026, 2, 23, 23, 1),
          lastRunAt: DateTime(2026, 2, 23, 23, 1),
          lastStatus: ScheduledTaskRunStatus.failed,
          lastError: 'boom',
          consecutiveFailures: 1,
        );
    final decoded = ScheduledTask.fromJson(item.toJson());
    expect(decoded.id, item.id);
    expect(decoded.time, item.time);
    expect(decoded.daysOfWeek, item.daysOfWeek);
    expect(decoded.nextRunAt, item.nextRunAt);
    expect(decoded.lastError, 'boom');
  });
}
