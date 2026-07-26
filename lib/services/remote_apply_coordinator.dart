/// Serializes remote operations that commit into shared local application data.
final class RemoteApplyCoordinator {
  Future<void> _tail = Future.value();

  Future<T> run<T>(Future<T> Function() action) {
    late T value;
    final operation = _tail.then((_) async {
      value = await action();
    });
    _tail = operation.catchError((Object _) {});
    return operation.then((_) => value);
  }
}
