import 'dart:async';

class FlushTaskFailure {
  const FlushTaskFailure(this.name, this.error, this.stackTrace);

  final String name;
  final Object error;
  final StackTrace stackTrace;
}

class FlushTasksException implements Exception {
  const FlushTasksException(this.failures);

  final List<FlushTaskFailure> failures;

  @override
  String toString() =>
      failures.map((failure) => '${failure.name}: ${failure.error}').join('; ');
}

Future<void> flushAllTasks(
  Iterable<({String name, Future<void> Function() flush})> tasks,
) async {
  final failures = <FlushTaskFailure>[];
  for (final task in tasks) {
    try {
      await task.flush();
    } catch (error, stackTrace) {
      failures.add(FlushTaskFailure(task.name, error, stackTrace));
    }
  }
  if (failures.isNotEmpty) {
    throw FlushTasksException(List.unmodifiable(failures));
  }
}
