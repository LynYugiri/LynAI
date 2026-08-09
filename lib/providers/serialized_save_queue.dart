import 'package:flutter/foundation.dart';

/// 串行保存队列混入。
///
/// 提供统一的 `Future<void>` 保存队列：每次 [enqueueSave] 都会串到队尾，
/// 失败不打断队列；[flushPendingSaves] 等待队尾原始操作，从而向上层
/// 传播保存错误。队列尾可通过 [pendingSaveQueue] 等待，供需要确保
/// 全部保存完成的调用点使用。
///
/// 需要延迟入队（防抖）或入队前收尾的 Provider 可覆写 [onBeforeFlush]，
/// 它会在 [flushPendingSaves] 等待队列前被调用。
mixin SerializedSaveQueue on ChangeNotifier {
  Future<void> _saveQueue = Future.value();
  Future<void> _pendingSave = Future.value();

  /// 把一次保存操作串到队列尾部，返回原始操作（保留错误传播）。
  @protected
  Future<void> enqueueSave(Future<void> Function() saver) {
    final operation = _saveQueue.then((_) => saver());
    _pendingSave = operation;
    _saveQueue = operation.catchError(onSaveQueueError);
    return operation;
  }

  /// 等待全部已入队保存完成；任何一次保存失败都会向上抛出。
  Future<void> flushPendingSaves() async {
    await onBeforeFlush();
    await _pendingSave;
  }

  /// 队列尾部（已吞掉失败的链）；用于只关心"都已落盘"的调用点。
  @protected
  Future<void> get pendingSaveQueue => _saveQueue;

  /// 在 [flushPendingSaves] 等待前执行；需要强制排空防抖快照时覆写。
  @protected
  Future<void> onBeforeFlush() async {}

  /// 保存失败处理；默认只打印，不打断队列。
  @protected
  void onSaveQueueError(Object error) {
    debugPrint('串行保存失败: $error');
  }
}
