import 'dart:async';

import 'package:shared_preferences/shared_preferences.dart';

import '../models/composer_reference.dart';

/// 按对话暂存输入框草稿。
///
/// 草稿是纯本地 UI 状态：它不属于 storage_v2 的会话数据，不进入普通/加密备份、
/// 云同步或 LAN 同步，也不随对话进入回收站。存储用 SharedPreferences，键按对话
/// ID 隔离，因此切换对话时各对话的草稿互不覆盖，进程结束再打开也能恢复。
///
/// 内存缓存是权威状态，写盘做防抖：连续输入只在停顿后落盘一次。切换对话、应用
/// 进入后台或退出前调用 [flush] 立即落盘。
class ComposerDraftService {
  /// 草稿键前缀，带格式版本号。
  static const _keyPrefix = 'chat.composer_draft.v1.';

  /// 尚未创建对话时使用的草稿槽位（[draftFor] 传 null）。
  static const _newConversationSlot = 'new';

  static const _flushDelay = Duration(milliseconds: 300);

  final Map<String, String> _drafts = {};
  final Set<String> _dirtySlots = {};
  Timer? _flushTimer;
  Future<void>? _loading;

  /// 读出全部草稿；重复调用复用同一次读取。
  ///
  /// 读盘失败（例如测试环境没有 SharedPreferences 插件）时草稿视为为空，输入框
  /// 照常可用。
  Future<void> ensureLoaded() {
    return _loading ??= _load();
  }

  Future<void> _load() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      for (final key in preferences.getKeys()) {
        if (!key.startsWith(_keyPrefix)) continue;
        final value = preferences.getString(key);
        if (value == null) continue;
        _drafts[key.substring(_keyPrefix.length)] = value;
      }
    } catch (_) {
      _drafts.clear();
    }
  }

  /// 读取某个对话的草稿；没有草稿或内容已损坏时返回空列表。
  List<ComposerSegment> draftFor(String? conversationId) {
    final json = _drafts[_slotOf(conversationId)];
    if (json == null) return const [];
    try {
      return decodeComposerSegments(json);
    } catch (_) {
      return const [];
    }
  }

  /// 暂存一个对话的草稿；片段为空时删除该对话的草稿。
  void saveDraft(String? conversationId, List<ComposerSegment> segments) {
    if (segments.isEmpty) {
      removeDraft(conversationId);
      return;
    }
    final slot = _slotOf(conversationId);
    final json = encodeComposerSegments(segments);
    if (_drafts[slot] == json) return;
    _drafts[slot] = json;
    _scheduleFlush(slot);
  }

  /// 删除一个对话的草稿（发送成功或对话被删除时调用）。
  void removeDraft(String? conversationId) {
    final slot = _slotOf(conversationId);
    if (_drafts.remove(slot) == null) return;
    _scheduleFlush(slot);
  }

  void _scheduleFlush(String slot) {
    _dirtySlots.add(slot);
    _flushTimer?.cancel();
    _flushTimer = Timer(_flushDelay, () => unawaited(flush()));
  }

  /// 立即把待写草稿落盘。
  Future<void> flush() async {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_dirtySlots.isEmpty) return;
    final slots = _dirtySlots.toList(growable: false);
    _dirtySlots.clear();
    try {
      final preferences = await SharedPreferences.getInstance();
      for (final slot in slots) {
        final json = _drafts[slot];
        if (json == null) {
          await preferences.remove('$_keyPrefix$slot');
        } else {
          await preferences.setString('$_keyPrefix$slot', json);
        }
      }
    } catch (_) {
      // 落盘失败不回滚内存草稿，也不影响正在进行的输入。
    }
  }

  static String _slotOf(String? conversationId) =>
      conversationId == null || conversationId.isEmpty
      ? _newConversationSlot
      : conversationId;
}
