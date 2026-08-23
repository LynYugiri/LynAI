import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/role_memory_entry.dart';
import '../repositories/role_memory_repository.dart';
import '../services/storage_v2_service.dart';
import 'serialized_save_queue.dart';

/// 角色隔离的长期记忆。
///
/// 记忆按 [RoleMemoryEntry.roleId] 完全隔离，每个角色下再分两个 target：
/// - memory：角色自己的笔记（环境事实、约定、经验）
/// - user：该角色视角下的用户画像（偏好、沟通风格）
///
/// 系统提示词每次请求注入最新记忆；写入后下一轮立即可见。
/// 保存使用统一的 [SerializedSaveQueue]，快照替换写入。
class RoleMemoryProvider extends ChangeNotifier with SerializedSaveQueue {
  static const targetMemory = RoleMemoryEntry.targetMemory;
  static const targetUser = RoleMemoryEntry.targetUser;
  static const entryDelimiter = '\n§\n';
  static const _maxConsolidationFailuresPerTurn = 3;

  final RoleMemoryRepository _repository;
  final _uuid = const Uuid();

  int memoryCharLimit;
  int userCharLimit;

  List<RoleMemoryEntry> _entries = [];
  int _mutationGeneration = 0;

  final Map<String, int> _consolidationFailures = {};
  final Map<String, int> _turnsSinceMemoryWrite = {};

  RoleMemoryProvider({
    StorageV2Service? storageV2,
    RoleMemoryRepository? repository,
    this.memoryCharLimit = 2200,
    this.userCharLimit = 1375,
  }) : _repository = repository ?? RoleMemoryRepository(storageV2: storageV2);

  List<RoleMemoryEntry> get allEntries => List.unmodifiable(_entries);

  List<RoleMemoryEntry> entriesFor(String roleId, String target) {
    if (!_validTarget(target)) return const [];
    return List.unmodifiable(
      _entries.where(
        (entry) => entry.roleId == roleId && entry.target == target,
      ),
    );
  }

  List<String> entryTextsFor(String roleId, String target) {
    return entriesFor(
      roleId,
      target,
    ).map((entry) => entry.entry).toList(growable: false);
  }

  int charCountFor(String roleId, String target) {
    return entryTextsFor(roleId, target).join(entryDelimiter).length;
  }

  String usageForEntries(String target, List<String> entries) {
    final current = entries.join(entryDelimiter).length;
    final limit = _charLimit(target);
    final pct = limit == 0 ? 0 : (current / limit * 100).floor().clamp(0, 100);
    return '$pct% — $current/$limit chars';
  }

  String usageText(String roleId, String target) {
    return usageForEntries(target, entryTextsFor(roleId, target));
  }

  String renderBlock(String roleId, String target) {
    if (!_validTarget(target)) return '';
    final texts = entryTextsFor(roleId, target);
    if (texts.isEmpty) return '';
    final header = target == targetMemory
        ? 'MEMORY (你的个人笔记) [${usageForEntries(target, texts)}]'
        : 'USER PROFILE (该角色视角下的用户画像) [${usageForEntries(target, texts)}]';
    final separator = '═' * 46;
    return '$separator\n$header\n$separator\n${texts.join(entryDelimiter)}';
  }

  /// 组装一个角色的完整注入块。
  String memoryBlockFor(
    String roleId, {
    bool includeMemory = true,
    bool includeUser = true,
  }) {
    final parts = [
      if (includeMemory) renderBlock(roleId, targetMemory),
      if (includeUser) renderBlock(roleId, targetUser),
    ].where((block) => block.trim().isNotEmpty).toList();
    return parts.join('\n\n');
  }

  Future<void> load() async {
    final generation = _mutationGeneration;
    await flushPendingSaves();
    final result = await _repository.load();
    if (generation != _mutationGeneration) return;
    final sorted = List.of(result.entries)
      ..sort((a, b) {
        final roleCompare = a.roleId.compareTo(b.roleId);
        if (roleCompare != 0) return roleCompare;
        final targetCompare = a.target.compareTo(b.target);
        if (targetCompare != 0) return targetCompare;
        return a.sortOrder.compareTo(b.sortOrder);
      });
    final seen = <String>{};
    _entries = [
      for (final entry in sorted)
        if (seen.add(
          '${entry.roleId}\u0000${entry.target}\u0000${entry.entry}',
        ))
          entry,
    ];
    _consolidationFailures.clear();
    _turnsSinceMemoryWrite.clear();
    notifyListeners();
  }

  void updateLimits({int? memory, int? user}) {
    if (memory != null) memoryCharLimit = memory;
    if (user != null) userCharLimit = user;
    notifyListeners();
  }

  /// 记录一轮用户输入；只有模型本轮具备 memory 工具时才调用。
  void noteUserTurn(String roleId) {
    _turnsSinceMemoryWrite[roleId] = (_turnsSinceMemoryWrite[roleId] ?? 0) + 1;
  }

  void resetConsolidationFailures(String roleId) {
    _consolidationFailures[roleId] = 0;
  }

  /// 达到 nudge 间隔时返回提示并重置计数；否则返回空字符串。
  String takeNudgeIfDue(String roleId, {required int nudgeInterval}) {
    if (nudgeInterval <= 0) return '';
    final turns = _turnsSinceMemoryWrite[roleId] ?? 0;
    if (turns < nudgeInterval) return '';
    _turnsSinceMemoryWrite[roleId] = 0;
    return '［记忆维护提醒］已经连续 $turns 轮没有写入持久记忆。'
        '结合本轮对话检查是否有值得保存的用户偏好、纠正、环境事实或约定：'
        '有就调用 memory 工具写入；没有就正常回答，不要为了写而写。';
  }

  /// 删除角色时级联删除其全部记忆。
  void removeRole(String roleId) {
    _consolidationFailures.remove(roleId);
    _turnsSinceMemoryWrite.remove(roleId);
    final before = _entries.length;
    _entries = _entries.where((entry) => entry.roleId != roleId).toList();
    if (_entries.length == before) return;
    _mutationGeneration++;
    _queueSnapshotSave();
    notifyListeners();
  }

  Map<String, dynamic> add(String roleId, String target, String content) {
    final trimmed = content.trim();
    if (!_validTarget(target)) return _invalidTarget(target);
    if (trimmed.isEmpty) return _error('内容不能为空。');
    final texts = entryTextsFor(roleId, target);
    if (texts.contains(trimmed)) {
      return _success(target, texts, '条目已存在，未重复添加。');
    }
    final working = List<String>.from(texts)..add(trimmed);
    final newTotal = working.join(entryDelimiter).length;
    if (newTotal > _charLimit(target)) {
      return _consolidationFailure(roleId, _overflow(target, texts, newTotal));
    }
    _replaceRoleTargetEntries(roleId, target, working);
    return _success(target, working, '条目已添加。');
  }

  Map<String, dynamic> replace(
    String roleId,
    String target,
    String oldText,
    String newContent,
  ) {
    if (!_validTarget(target)) return _invalidTarget(target);
    final oldTrim = oldText.trim();
    final newTrim = newContent.trim();
    if (oldTrim.isEmpty) return _error('old_text 不能为空。');
    if (newTrim.isEmpty) {
      return _error('new_content 不能为空；删除条目请使用 remove。');
    }
    final texts = entryTextsFor(roleId, target);
    final matches = [
      for (var i = 0; i < texts.length; i++)
        if (texts[i].contains(oldTrim)) i,
    ];
    if (matches.isEmpty) {
      return _consolidationFailure(
        roleId,
        _errorWithEntries(target, texts, '没有条目匹配 “$oldTrim”。'),
      );
    }
    final distinct = matches.map((i) => texts[i]).toSet();
    if (distinct.length > 1) {
      return _error('“$oldTrim” 匹配到多条不同条目，请提供更精确的子串。');
    }
    final working = List<String>.from(texts);
    working[matches.first] = newTrim;
    final newTotal = working.join(entryDelimiter).length;
    if (newTotal > _charLimit(target)) {
      return _consolidationFailure(roleId, _overflow(target, texts, newTotal));
    }
    _replaceRoleTargetEntries(roleId, target, working);
    return _success(target, working, '条目已替换。');
  }

  Map<String, dynamic> remove(String roleId, String target, String oldText) {
    if (!_validTarget(target)) return _invalidTarget(target);
    final oldTrim = oldText.trim();
    if (oldTrim.isEmpty) return _error('old_text 不能为空。');
    final texts = entryTextsFor(roleId, target);
    final matches = [
      for (var i = 0; i < texts.length; i++)
        if (texts[i].contains(oldTrim)) i,
    ];
    if (matches.isEmpty) {
      return _consolidationFailure(
        roleId,
        _errorWithEntries(target, texts, '没有条目匹配 “$oldTrim”。'),
      );
    }
    final distinct = matches.map((i) => texts[i]).toSet();
    if (distinct.length > 1) {
      return _error('“$oldTrim” 匹配到多条不同条目，请提供更精确的子串。');
    }
    final working = List<String>.from(texts)..removeAt(matches.first);
    _replaceRoleTargetEntries(roleId, target, working);
    return _success(target, working, '条目已删除。');
  }

  Map<String, dynamic> applyBatch(
    String roleId,
    String target,
    List<Map<String, dynamic>> operations,
  ) {
    if (!_validTarget(target)) return _invalidTarget(target);
    if (operations.isEmpty) return _error('operations 列表为空。');
    final texts = entryTextsFor(roleId, target);
    final working = List<String>.from(texts);

    for (var i = 0; i < operations.length; i++) {
      final op = operations[i];
      final pos = '操作 ${i + 1} (${op['action'] ?? 'unknown'})';
      final action = op['action'];
      final content = ((op['content'] ?? op['new_text']) as String? ?? '')
          .trim();
      final oldText = (op['old_text'] as String? ?? '').trim();

      switch (action) {
        case 'add':
          if (content.isEmpty) return _error('$pos: content 不能为空。');
          if (working.contains(content)) continue;
          working.add(content);
          break;
        case 'replace':
          if (oldText.isEmpty) return _error('$pos: old_text 不能为空。');
          if (content.isEmpty) {
            return _error('$pos: content 不能为空；删除请用 remove。');
          }
          final matches = [
            for (var j = 0; j < working.length; j++)
              if (working[j].contains(oldText)) j,
          ];
          if (matches.isEmpty) {
            return _consolidationFailure(
              roleId,
              _error('$pos: 没有条目匹配 “$oldText”。'),
            );
          }
          final distinct = matches.map((j) => working[j]).toSet();
          if (distinct.length > 1) {
            return _error('$pos: “$oldText” 匹配到多条不同条目。');
          }
          working[matches.first] = content;
          break;
        case 'remove':
          if (oldText.isEmpty) return _error('$pos: old_text 不能为空。');
          final matches = [
            for (var j = 0; j < working.length; j++)
              if (working[j].contains(oldText)) j,
          ];
          if (matches.isEmpty) {
            return _consolidationFailure(
              roleId,
              _error('$pos: 没有条目匹配 “$oldText”。'),
            );
          }
          final distinct = matches.map((j) => working[j]).toSet();
          if (distinct.length > 1) {
            return _error('$pos: “$oldText” 匹配到多条不同条目。');
          }
          working.removeAt(matches.first);
          break;
        default:
          return _error('$pos: 未知操作。请使用 add、replace、remove。');
      }
    }

    final newTotal = working.join(entryDelimiter).length;
    if (newTotal > _charLimit(target)) {
      return _consolidationFailure(
        roleId,
        _errorWithEntries(
          target,
          texts,
          '应用全部 ${operations.length} 个操作后记忆将达到 '
          '$newTotal/${_charLimit(target)} 字符，超出预算。'
          '请在同一批次中删除或精简更多条目。',
        ),
      );
    }
    _replaceRoleTargetEntries(roleId, target, working);
    return _success(target, working, '已应用 ${operations.length} 个操作。');
  }

  void _replaceRoleTargetEntries(
    String roleId,
    String target,
    List<String> texts,
  ) {
    final now = DateTime.now();
    final kept = _entries.where(
      (entry) => entry.roleId != roleId || entry.target != target,
    );
    final next = <RoleMemoryEntry>[
      ...kept,
      for (var i = 0; i < texts.length; i++)
        RoleMemoryEntry(
          id: _uuid.v4(),
          roleId: roleId,
          target: target,
          entry: texts[i],
          sortOrder: i,
          createdAt: now,
          updatedAt: now,
        ),
    ];
    _entries = next;
    _markMemoryWritten(roleId);
    _mutationGeneration++;
    _queueSnapshotSave();
    notifyListeners();
  }

  void _queueSnapshotSave() {
    final snapshot = List<RoleMemoryEntry>.from(_entries);
    enqueueSave(() => _repository.replace(snapshot));
  }

  void _markMemoryWritten(String roleId) {
    _turnsSinceMemoryWrite[roleId] = 0;
    _consolidationFailures[roleId] = 0;
  }

  bool _validTarget(String target) =>
      target == targetMemory || target == targetUser;

  int _charLimit(String target) =>
      target == targetUser ? userCharLimit : memoryCharLimit;

  Map<String, dynamic> _invalidTarget(String target) {
    return _error('无效 target “$target”。请使用 “$targetMemory” 或 “$targetUser”。');
  }

  Map<String, dynamic> _error(String message) {
    return {'success': false, 'error': message};
  }

  Map<String, dynamic> _errorWithEntries(
    String target,
    List<String> entries,
    String message,
  ) {
    return {
      'success': false,
      'error': message,
      'current_entries': List<String>.from(entries),
      'usage': usageForEntries(target, entries),
    };
  }

  Map<String, dynamic> _overflow(
    String target,
    List<String> entries,
    int newTotal,
  ) {
    final limit = _charLimit(target);
    final current = entries.join(entryDelimiter).length;
    return {
      'success': false,
      'error':
          '记忆当前 $current/$limit 字符，写入后会达到 $newTotal/$limit 字符，'
          '超出预算。请先用 replace 合并重复条目或 remove 删除过时条目，'
          '然后在同一批 operations 中完成写入。',
      'current_entries': List<String>.from(entries),
      'usage': usageForEntries(target, entries),
    };
  }

  Map<String, dynamic> _consolidationFailure(
    String roleId,
    Map<String, dynamic> response,
  ) {
    final failures = (_consolidationFailures[roleId] ?? 0) + 1;
    _consolidationFailures[roleId] = failures;
    if (failures <= _maxConsolidationFailuresPerTurn) return response;
    return {
      'success': false,
      'done': true,
      'error':
          '记忆合并已经连续失败 $failures 次，本轮停止重试 memory 工具，'
          '先正常回复用户；这些事实可以以后再保存。',
      'current_entries': response['current_entries'],
      'usage': response['usage'],
    };
  }

  Map<String, dynamic> _success(
    String target,
    List<String> entries,
    String message,
  ) {
    return {
      'success': true,
      'done': true,
      'target': target,
      'usage': usageForEntries(target, entries),
      'entry_count': entries.length,
      'message': message,
      'note': '写入已保存，本次更新完成，请勿重复。',
    };
  }
}
