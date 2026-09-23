import 'package:flutter/widgets.dart';

import '../models/composer_reference.dart';
import '../models/knowledge_entry.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/knowledge_provider.dart';
import '../providers/task_provider.dart';

/// 选择器条目类型：实体或文件夹。
///
/// 文件夹条目既可以进入下一级，也可以被直接引用（引用整个文件夹）；是否
/// 携带 [ComposerSelectorItem.value] 决定它能否被引用。
enum ComposerSelectorItemKind { item, folder }

/// 内置选择器种类，供 [buildBuiltInSelectorRegistry] 按使用场景裁剪。
enum BuiltInComposerSelector {
  notes,
  notePages,
  taskLists,
  tasks,
  knowledgeBases,
  knowledgeEntries,
  conversations,
}

/// 选择器返回的稳定值：含类型、稳定 ID 与展示摘要，不含正文。
class ComposerSelectorValue {
  final ComposerReferenceType type;
  final String id;
  final String title;
  final String? subtitle;

  /// 内容摘要（如正文首行），供随记等非对话场景生成引用卡片快照。
  final String? snippet;

  /// 分级层级：在容器（文件夹）层停下就是引用整个容器。
  final ComposerReferenceScope scope;

  final Map<String, String> qualifiers;

  const ComposerSelectorValue({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
    this.snippet,
    this.scope = ComposerReferenceScope.entity,
    this.qualifiers = const {},
  });
}

/// 选择器条目：文件夹用于导航，实体用于选中并产生引用。
class ComposerSelectorItem {
  final String key;
  final ComposerSelectorItemKind kind;
  final String title;
  final String? subtitle;
  final ComposerSelectorValue? value;

  const ComposerSelectorItem({
    required this.key,
    required this.kind,
    required this.title,
    this.subtitle,
    this.value,
  });
}

/// 一个内置选择器的声明。
class ComposerSelector {
  final String name;

  /// 面板中显示的标题，默认回退到 [name]。
  final String title;

  /// 面板中显示的说明文字。
  final String description;

  /// 列表前置的图标；为空时按标题首字显示。
  ///
  /// 插件数据源用它标注自己的来源，内置源留空。
  final IconData? icon;

  /// 选择该 selector 生成的引用后，本次发送应覆盖使用的模型 ID（插件命令用）。
  final String? modelId;

  /// 返回当前层级的条目；[query] 用于过滤，[path] 是导航路径。
  ///
  /// 异步返回以同时支持内置选择器（同步读取内存 Provider）与插件命令
  /// （需异步执行 Lua handler）。
  final Future<List<ComposerSelectorItem>> Function(
    String query,
    List<String> path,
  )
  load;

  /// 当前层级本身对应的引用（如「引用整个文件夹」）；null 表示该层没有范围引用。
  ///
  /// 面板会把它渲染成列表首位的一条范围条目，用户不必继续下钻即可引用整层。
  final ComposerSelectorValue? Function(List<String> path)? rootValue;

  const ComposerSelector({
    required this.name,
    required this.load,
    this.title = '',
    this.description = '',
    this.icon,
    this.modelId,
    this.rootValue,
  });
}

/// 选择器注册表：承载内置与插件提供的选择器。
class ComposerSelectorRegistry {
  final Map<String, ComposerSelector> _selectors = {};

  void register(ComposerSelector selector) =>
      _selectors[selector.name] = selector;

  ComposerSelector? selector(String name) => _selectors[name];

  Iterable<String> get names => _selectors.keys;

  /// 面板展示用的所有选择器，按注册顺序。
  Iterable<ComposerSelector> get selectors => _selectors.values;
}

/// 构建内置选择器注册表（笔记、待办清单、待办项、知识库、对话记录）。
///
/// [include] 为空时注册全部内置选择器；随记等场景可只注册能映射到自身引用
/// 类型的子集，同时保留文件夹分层导航。
///
/// [conversations] 非空时注册「对话记录」选择器（引用一段历史对话）；
/// [currentConversationId] 用于在列表中排除当前对话本身。
ComposerSelectorRegistry buildBuiltInSelectorRegistry({
  required FeatureProvider features,
  required TaskProvider tasks,
  KnowledgeProvider? knowledge,
  ConversationProvider? conversations,
  String? currentConversationId,
  Set<BuiltInComposerSelector>? include,
}) {
  final wanted = include ?? BuiltInComposerSelector.values.toSet();
  final registry = ComposerSelectorRegistry();
  if (wanted.contains(BuiltInComposerSelector.notes)) {
    registry.register(
      ComposerSelector(
        name: 'notes',
        title: '笔记',
        description: '引用一篇笔记，或停在文件夹层引用整个文件夹',
        load: (query, path) async => _loadNotes(features, query, path),
        rootValue: (path) => _notesRootValue(features, path),
      ),
    );
  }
  if (wanted.contains(BuiltInComposerSelector.notePages)) {
    registry.register(
      ComposerSelector(
        name: 'note-pages',
        title: '笔记页面',
        description: '引用笔记中的某一页',
        load: (query, path) async => _loadNotePages(features, query, path),
      ),
    );
  }
  if (wanted.contains(BuiltInComposerSelector.taskLists)) {
    registry.register(
      ComposerSelector(
        name: 'task-lists',
        title: '待办清单',
        description: '引用一个待办清单',
        load: (query, path) async => _loadTaskLists(tasks, query),
      ),
    );
  }
  if (wanted.contains(BuiltInComposerSelector.tasks)) {
    registry.register(
      ComposerSelector(
        name: 'tasks',
        title: '待办事项',
        description: '引用一个待办事项',
        load: (query, path) async => _loadTasks(tasks, query, path),
      ),
    );
  }
  if (knowledge != null &&
      wanted.contains(BuiltInComposerSelector.knowledgeBases)) {
    registry.register(
      ComposerSelector(
        name: 'knowledge-bases',
        title: '知识库',
        description: '引用整个知识库',
        load: (query, path) async => _loadKnowledgeBases(knowledge, query),
      ),
    );
  }
  if (knowledge != null &&
      wanted.contains(BuiltInComposerSelector.knowledgeEntries)) {
    registry.register(
      ComposerSelector(
        name: 'knowledge-entries',
        title: '知识条目',
        description: '浏览知识库并引用具体条目',
        load: (query, path) async =>
            _loadKnowledgeEntries(knowledge, query, path),
      ),
    );
  }
  if (conversations != null &&
      wanted.contains(BuiltInComposerSelector.conversations)) {
    registry.register(
      ComposerSelector(
        name: 'conversations',
        title: '对话',
        description: '引用一段历史对话',
        load: (query, path) async => _loadConversations(
          conversations,
          query,
          currentConversationId,
        ),
      ),
    );
  }
  return registry;
}

/// 笔记选择器当前层的范围引用：在文件夹层停下即引用整个文件夹。
ComposerSelectorValue? _notesRootValue(
  FeatureProvider features,
  List<String> path,
) {
  if (path.isEmpty) return null;
  final folderId = path.first;
  for (final folder in features.noteFolders) {
    if (folder.id != folderId) continue;
    final count = features.notes
        .where((note) => note.folderId == folderId)
        .length;
    return ComposerSelectorValue(
      type: ComposerReferenceType.note,
      id: folder.id,
      title: folder.title,
      subtitle: '$count 篇笔记',
      scope: ComposerReferenceScope.folder,
    );
  }
  return null;
}

/// 把选择器值转成编辑器引用；[localId] 由调用方按自增序号分配。
ComposerReference composerReferenceFromValue(
  ComposerSelectorValue value, {
  required String localId,
}) => ComposerReference(
  localId: localId,
  type: value.type,
  id: value.id,
  title: value.title,
  subtitle: value.subtitle,
  scope: value.scope,
  qualifiers: value.qualifiers,
);

bool _matches(String? value, String query) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return true;
  return value?.toLowerCase().contains(q) == true;
}

String _noteSubtitle(Note note) {
  final collapsed = note.content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return '';
  return collapsed.length > 80 ? '${collapsed.substring(0, 80)}…' : collapsed;
}

String _firstNonEmptyLine(String content) {
  return content
      .split('\n')
      .map((line) => line.trim())
      .firstWhere((line) => line.isNotEmpty, orElse: () => '');
}

List<ComposerSelectorItem> _noteItem(Note note) => [
  ComposerSelectorItem(
    key: 'note:${note.id}',
    kind: ComposerSelectorItemKind.item,
    title: note.title,
    subtitle: _noteSubtitle(note),
    value: ComposerSelectorValue(
      type: ComposerReferenceType.note,
      id: note.id,
      title: note.title,
      subtitle: _noteSubtitle(note),
      snippet: _firstNonEmptyLine(note.content),
    ),
  ),
];

List<ComposerSelectorItem> _loadNotes(
  FeatureProvider features,
  String query,
  List<String> path,
) {
  if (path.isNotEmpty) {
    final folderId = path.first;
    return features.notes
        .where((note) => note.folderId == folderId)
        .where((note) => _matches(note.title, query))
        .expand(_noteItem)
        .toList();
  }
  final items = <ComposerSelectorItem>[];
  for (final folder in features.noteFolders) {
    if (!_matches(folder.title, query)) continue;
    final count = features.notes
        .where((note) => note.folderId == folder.id)
        .length;
    items.add(
      ComposerSelectorItem(
        key: 'folder:${folder.id}',
        kind: ComposerSelectorItemKind.folder,
        title: folder.title,
        subtitle: '$count 篇笔记',
        value: ComposerSelectorValue(
          type: ComposerReferenceType.note,
          id: folder.id,
          title: folder.title,
          subtitle: '$count 篇笔记',
          scope: ComposerReferenceScope.folder,
        ),
      ),
    );
  }
  for (final note in features.notes) {
    if (note.folderId != null) continue;
    if (_matches(note.title, query) || _matches(_noteSubtitle(note), query)) {
      items.addAll(_noteItem(note));
    }
  }
  return items;
}

List<ComposerSelectorItem> _loadNotePages(
  FeatureProvider features,
  String query,
  List<String> path,
) {
  if (path.isEmpty) {
    // 页面挂在笔记下：先列出笔记，进入某篇后再列它的页面。
    return features.notes
        .where((note) => _matches(note.title, query))
        .map(
          (note) => ComposerSelectorItem(
            key: 'note-folder:${note.id}',
            kind: ComposerSelectorItemKind.folder,
            title: note.title,
            subtitle: _noteSubtitle(note),
          ),
        )
        .toList();
  }
  final noteId = path.first;
  return features
      .notePages(noteId)
      .where((page) => _matches(page.title, query))
      .map(
        (page) => ComposerSelectorItem(
          key: 'page:${page.id}',
          kind: ComposerSelectorItemKind.item,
          title: page.title,
          value: ComposerSelectorValue(
            type: ComposerReferenceType.notePage,
            id: page.id,
            title: page.title,
            qualifiers: {'noteId': noteId},
          ),
        ),
      )
      .toList();
}

List<ComposerSelectorItem> _loadTaskLists(TaskProvider tasks, String query) {
  return tasks.lists
      .where((list) => _matches(list.title, query))
      .map(
        (list) => ComposerSelectorItem(
          key: 'list:${list.id}',
          kind: ComposerSelectorItemKind.item,
          title: list.title,
          subtitle: '${tasks.tasksForList(list.id).length} 个待办',
          value: ComposerSelectorValue(
            type: ComposerReferenceType.taskList,
            id: list.id,
            title: list.title,
          ),
        ),
      )
      .toList();
}

ComposerSelectorItem _taskItem(Task task) {
  final state = task.isCompleted ? '已完成' : '未完成';
  return ComposerSelectorItem(
    key: 'task:${task.id}',
    kind: ComposerSelectorItemKind.item,
    title: task.title,
    subtitle: state,
    value: ComposerSelectorValue(
      type: ComposerReferenceType.task,
      id: task.id,
      title: task.title,
      subtitle: state,
      snippet: _firstNonEmptyLine(task.note ?? ''),
    ),
  );
}

List<ComposerSelectorItem> _loadTasks(
  TaskProvider tasks,
  String query,
  List<String> path,
) {
  if (path.isNotEmpty) {
    final listId = path.first;
    return tasks
        .tasksForList(listId)
        .where((task) => _matches(task.title, query))
        .map(_taskItem)
        .toList();
  }
  final items = <ComposerSelectorItem>[];
  for (final list in tasks.lists) {
    if (_matches(list.title, query)) {
      final count = tasks.tasksForList(list.id).length;
      final subtitle = '$count 个待办';
      items.add(
        ComposerSelectorItem(
          key: 'list:${list.id}',
          kind: ComposerSelectorItemKind.folder,
          title: list.title,
          subtitle: subtitle,
          // 停在清单层就是引用整个清单；继续下钻则引用单条待办。
          value: ComposerSelectorValue(
            type: ComposerReferenceType.taskList,
            id: list.id,
            title: list.title,
            subtitle: subtitle,
          ),
        ),
      );
    }
  }
  for (final task in tasks.unlistedTasks) {
    if (_matches(task.title, query)) {
      items.add(_taskItem(task));
    }
  }
  return items;
}

String _knowledgeEntrySubtitle(KnowledgeEntry entry) {
  final collapsed = entry.content.replaceAll(RegExp(r'\s+'), ' ').trim();
  if (collapsed.isEmpty) return '';
  return collapsed.length > 80 ? '${collapsed.substring(0, 80)}…' : collapsed;
}

List<ComposerSelectorItem> _loadKnowledgeBases(
  KnowledgeProvider knowledge,
  String query,
) {
  return knowledge.knowledgeBases
      .where((base) => _matches(base.name, query))
      .map(
        (base) => ComposerSelectorItem(
          key: 'knowledge-base:${base.id}',
          kind: ComposerSelectorItemKind.item,
          title: base.name,
          subtitle: '${knowledge.entriesForBase(base.id).length} 个条目',
          value: ComposerSelectorValue(
            type: ComposerReferenceType.knowledgeBase,
            id: base.id,
            title: base.name,
          ),
        ),
      )
      .toList();
}

List<ComposerSelectorItem> _loadKnowledgeEntries(
  KnowledgeProvider knowledge,
  String query,
  List<String> path,
) {
  if (path.isNotEmpty) {
    final baseId = path.first;
    return knowledge
        .entriesForBase(baseId)
        .where(
          (entry) =>
              _matches(entry.title, query) ||
              _matches(_knowledgeEntrySubtitle(entry), query),
        )
        .map(
          (entry) => ComposerSelectorItem(
            key: 'knowledge-entry:${entry.id}',
            kind: ComposerSelectorItemKind.item,
            title: entry.title,
            subtitle: _knowledgeEntrySubtitle(entry),
            value: ComposerSelectorValue(
              type: ComposerReferenceType.knowledgeEntry,
              id: entry.id,
              title: entry.title,
              subtitle: _knowledgeEntrySubtitle(entry),
              snippet: _firstNonEmptyLine(entry.content),
            ),
          ),
        )
        .toList();
  }
  return knowledge.knowledgeBases
      .where((base) => _matches(base.name, query))
      .map(
        (base) => ComposerSelectorItem(
          key: 'knowledge-base-folder:${base.id}',
          kind: ComposerSelectorItemKind.folder,
          title: base.name,
          subtitle: '${knowledge.entriesForBase(base.id).length} 个条目',
        ),
      )
      .toList();
}

/// 对话选择器：列出历史对话供引用，最近更新的排在前面。
///
/// 排除 [currentConversationId] 本身：引用「当前这段对话」没有意义，而且
/// 会让模型去读自己正在写的上下文。
List<ComposerSelectorItem> _loadConversations(
  ConversationProvider conversations,
  String query,
  String? currentConversationId,
) {
  final list = conversations.conversations
      .where((conversation) => conversation.id != currentConversationId)
      .where((conversation) => conversation.messages.isNotEmpty)
      .toList()
    ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
  final items = <ComposerSelectorItem>[];
  for (final conversation in list) {
    if (!_matches(conversation.title, query) &&
        !_matches(conversation.preview, query)) {
      continue;
    }
    items.add(
      ComposerSelectorItem(
        key: 'conversation:${conversation.id}',
        kind: ComposerSelectorItemKind.item,
        title: conversation.title.isEmpty ? '未命名对话' : conversation.title,
        subtitle: '${conversation.messages.length} 条消息',
        value: ComposerSelectorValue(
          type: ComposerReferenceType.conversation,
          id: conversation.id,
          title: conversation.title.isEmpty ? '未命名对话' : conversation.title,
          subtitle: '${conversation.messages.length} 条消息',
          snippet: conversation.preview,
        ),
      ),
    );
  }
  return items;
}

/// 解析插件命令 handler 的返回结果为选择器条目。
///
/// 兼容 `{ok:true, result:[...]}`、`{ok:true, options:[...]}` 与直接返回
/// 数组三种形态；`ok:false` 或结构非法时返回空列表（fail closed）。
List<ComposerSelectorItem> parsePluginCommandItems(Object? data) {
  final options = _extractCommandOptions(data);
  final items = <ComposerSelectorItem>[];
  for (final raw in options) {
    if (raw is! Map) continue;
    final map = raw.map((key, value) => MapEntry(key.toString(), value));
    final title = map['title']?.toString() ?? '';
    final subtitle = map['subtitle']?.toString();
    final kind = map['kind']?.toString() == 'folder'
        ? ComposerSelectorItemKind.folder
        : ComposerSelectorItemKind.item;
    final key =
        map['key']?.toString() ??
        (kind == ComposerSelectorItemKind.folder
            ? 'folder:$title'
            : 'item:$title');
    if (kind == ComposerSelectorItemKind.folder) {
      if (title.isEmpty) continue;
      items.add(
        ComposerSelectorItem(
          key: key,
          kind: kind,
          title: title,
          subtitle: subtitle,
        ),
      );
      continue;
    }
    final type = ComposerReferenceType.fromWire(map['type']?.toString());
    final id = map['id']?.toString() ?? '';
    if (type == null || id.isEmpty || title.isEmpty) continue;
    final qualifiers = <String, String>{};
    if (map['qualifiers'] is Map) {
      (map['qualifiers'] as Map).forEach(
        (qKey, qValue) => qualifiers[qKey.toString()] = qValue.toString(),
      );
    }
    items.add(
      ComposerSelectorItem(
        key: key,
        kind: kind,
        title: title,
        subtitle: subtitle,
        value: ComposerSelectorValue(
          type: type,
          id: id,
          title: title,
          subtitle: subtitle,
          qualifiers: qualifiers,
        ),
      ),
    );
  }
  return items;
}

List<dynamic> _extractCommandOptions(Object? data) {
  if (data is List) return data;
  if (data is! Map) return const [];
  if (data['ok'] == false) return const [];
  for (final key in const ['options', 'result', 'items']) {
    final value = data[key];
    if (value is List) return value;
  }
  return const [];
}
