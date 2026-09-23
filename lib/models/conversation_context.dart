import 'composer_reference.dart';

/// 一次手动上下文压缩的结果（`/压缩` 指令）。
///
/// 这是**对话级检查点**：原始消息一条都不删除，发送时用 [coveredMessageIds]
/// 标出的那段历史整体换成 [summary]。因此界面可以继续展示完整历史，用户也能
/// 随时清除检查点恢复原始上下文。
///
/// 与自动压缩的区别：自动压缩（`ModelContextCompactor` + `AgentContextBuilder`）
/// 只在单次请求内临时顶替被裁剪的历史，不落盘；本检查点持久化在对话数据里，
/// 随对话备份与云/LAN 同步。
class ConversationContextCheckpoint {
  /// 摘要正文。
  final String summary;

  /// 被摘要覆盖的消息 ID，按对话中的出现顺序。
  final List<String> coveredMessageIds;

  /// 生成时间。
  final DateTime createdAt;

  /// 生成摘要使用的模型配置 ID，仅用于展示与排查。
  final String modelId;

  const ConversationContextCheckpoint({
    required this.summary,
    required this.coveredMessageIds,
    required this.createdAt,
    this.modelId = '',
  });

  bool get isEmpty => summary.trim().isEmpty || coveredMessageIds.isEmpty;

  int get coveredCount => coveredMessageIds.length;

  /// 摘要被后续编辑/撤回影响后，收敛到仍然有效的覆盖集合。
  ///
  /// 返回 null 表示覆盖集合已为空，检查点应当被清除。
  ConversationContextCheckpoint? withCoveredMessages(
    Iterable<String> messageIds,
  ) {
    final alive = messageIds.toSet();
    final next = coveredMessageIds
        .where(alive.contains)
        .toList(growable: false);
    if (next.isEmpty) return null;
    if (next.length == coveredMessageIds.length) return this;
    return ConversationContextCheckpoint(
      summary: summary,
      coveredMessageIds: next,
      createdAt: createdAt,
      modelId: modelId,
    );
  }

  Map<String, dynamic> toJson() => {
    'summary': summary,
    'coveredMessageIds': coveredMessageIds,
    'createdAt': createdAt.toIso8601String(),
    if (modelId.isNotEmpty) 'modelId': modelId,
  };

  static ConversationContextCheckpoint? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final summary = raw['summary']?.toString() ?? '';
    final createdAt = DateTime.tryParse(raw['createdAt']?.toString() ?? '');
    final covered = (raw['coveredMessageIds'] as List<dynamic>? ?? const [])
        .map((item) => item.toString())
        .where((item) => item.isNotEmpty)
        .toList(growable: false);
    if (summary.trim().isEmpty || createdAt == null || covered.isEmpty) {
      return null;
    }
    return ConversationContextCheckpoint(
      summary: summary,
      coveredMessageIds: covered,
      createdAt: createdAt,
      modelId: raw['modelId']?.toString() ?? '',
    );
  }
}

/// 会话引用池里的一个条目。
///
/// 池子是**后台的引用账本**：用户在对话里引用过的资源自动沉淀到这里，独立于
/// 消息上下文，不进入 `buildApiMessages`，也不受上下文压缩影响。模型可以调用
/// `list_conversation_references` 查询清单，再按 id 用对应工具读取正文。
class ConversationReferenceEntry {
  final ComposerReferenceType type;
  final String id;
  final String title;
  final String? subtitle;
  final ComposerReferenceScope scope;
  final Map<String, String> qualifiers;

  /// 最近一次被引用的时间，用于同池上限的淘汰顺序。
  final DateTime addedAt;

  const ConversationReferenceEntry({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.scope = ComposerReferenceScope.entity,
    this.qualifiers = const {},
    required this.addedAt,
  });

  factory ConversationReferenceEntry.fromReference(
    ComposerReference reference, {
    required DateTime addedAt,
  }) => ConversationReferenceEntry(
    type: reference.type,
    id: reference.id,
    title: reference.title,
    subtitle: reference.subtitle,
    scope: reference.scope,
    qualifiers: reference.qualifiers,
    addedAt: addedAt,
  );

  /// 去重键：同一资源的同一层级只保留一条。
  String get key => '${type.wire}:${scope.wire}:$id';

  /// 模型侧展示用的范围说明，避免模型把文件夹当成单个实体去读。
  String get scopeLabel =>
      scope == ComposerReferenceScope.folder ? 'folder' : 'entity';

  Map<String, dynamic> toJson() => {
    'type': type.wire,
    'id': id,
    'title': title,
    if (subtitle != null) 'subtitle': subtitle,
    if (scope != ComposerReferenceScope.entity) 'scope': scope.wire,
    if (qualifiers.isNotEmpty) 'qualifiers': qualifiers,
    'addedAt': addedAt.toIso8601String(),
  };

  static ConversationReferenceEntry? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final type = ComposerReferenceType.fromWire(raw['type']?.toString());
    final id = raw['id']?.toString() ?? '';
    if (type == null || id.isEmpty) return null;
    return ConversationReferenceEntry(
      type: type,
      id: id,
      title: raw['title']?.toString() ?? '',
      subtitle: raw['subtitle']?.toString(),
      scope: ComposerReferenceScope.fromWire(raw['scope']?.toString()),
      qualifiers: (raw['qualifiers'] as Map? ?? const {}).map(
        (key, value) => MapEntry(key.toString(), value.toString()),
      ),
      addedAt:
          DateTime.tryParse(raw['addedAt']?.toString() ?? '') ?? DateTime.now(),
    );
  }
}

/// 会话引用池：按去重键合并、按上限淘汰最久未用条目。
///
/// 纯函数式的不可变集合，便于测试与在 Provider 中原子替换。
class ConversationReferencePool {
  /// 单个对话最多保留的引用条目数。
  static const maxEntries = 50;

  final List<ConversationReferenceEntry> entries;

  const ConversationReferencePool({this.entries = const []});

  bool get isEmpty => entries.isEmpty;

  int get length => entries.length;

  /// 合并新引用：同键更新标题与时间为「最近」，并裁到上限。
  ///
  /// 顺序保持「最先加入的在前」，被淘汰的是最久未被引用的条目。
  ConversationReferencePool merged(
    Iterable<ComposerReference> references, {
    required DateTime now,
  }) {
    final next = <String, ConversationReferenceEntry>{
      for (final entry in entries) entry.key: entry,
    };
    for (final reference in references) {
      if (reference.id.isEmpty) continue;
      next[reference.poolKey] = ConversationReferenceEntry.fromReference(
        reference,
        addedAt: now,
      );
    }
    final merged = next.values.toList()
      ..sort((a, b) => a.addedAt.compareTo(b.addedAt));
    final bounded = merged.length > maxEntries
        ? merged.sublist(merged.length - maxEntries)
        : merged;
    return ConversationReferencePool(entries: List.unmodifiable(bounded));
  }

  List<Map<String, dynamic>> toJson() => [
    for (final entry in entries) entry.toJson(),
  ];

  static ConversationReferencePool fromJson(Object? raw) {
    if (raw is! List) return const ConversationReferencePool();
    final parsed = <ConversationReferenceEntry>[];
    for (final item in raw) {
      final entry = ConversationReferenceEntry.fromJson(item);
      if (entry != null) parsed.add(entry);
    }
    return ConversationReferencePool(entries: List.unmodifiable(parsed));
  }
}
