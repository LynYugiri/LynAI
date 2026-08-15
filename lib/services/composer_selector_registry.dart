import '../models/composer_reference.dart';
import '../models/note.dart';
import '../models/task.dart';
import '../providers/feature_provider.dart';
import '../providers/task_provider.dart';

/// 选择器条目类型：实体或文件夹。
enum ComposerSelectorItemKind { item, folder }

/// 选择器返回的稳定值：只含类型与稳定 ID，不含正文。
class ComposerSelectorValue {
  final ComposerReferenceType type;
  final String id;
  final String title;
  final String? subtitle;
  final Map<String, String> qualifiers;

  const ComposerSelectorValue({
    required this.type,
    required this.id,
    required this.title,
    this.subtitle,
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

  const ComposerSelector({
    required this.name,
    required this.load,
    this.title = '',
    this.description = '',
    this.modelId,
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

/// 构建内置选择器注册表（笔记、笔记页面、待办清单、待办项）。
ComposerSelectorRegistry buildBuiltInSelectorRegistry({
  required FeatureProvider features,
  required TaskProvider tasks,
}) {
  final registry = ComposerSelectorRegistry();
  registry.register(
    ComposerSelector(
      name: 'notes',
      title: '笔记',
      description: '引用一篇笔记',
      load: (query, path) async => _loadNotes(features, query, path),
    ),
  );
  registry.register(
    ComposerSelector(
      name: 'note-pages',
      title: '笔记页面',
      description: '引用笔记中的某一页',
      load: (query, path) async => _loadNotePages(features, query, path),
    ),
  );
  registry.register(
    ComposerSelector(
      name: 'task-lists',
      title: '待办清单',
      description: '引用一个待办清单',
      load: (query, path) async => _loadTaskLists(tasks, query),
    ),
  );
  registry.register(
    ComposerSelector(
      name: 'tasks',
      title: '待办事项',
      description: '引用一个待办事项',
      load: (query, path) async => _loadTasks(tasks, query, path),
    ),
  );
  return registry;
}

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
    if (_matches(folder.title, query)) {
      items.add(
        ComposerSelectorItem(
          key: 'folder:${folder.id}',
          kind: ComposerSelectorItemKind.folder,
          title: folder.title,
        ),
      );
    }
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
  final noteId = path.isEmpty ? '' : path.first;
  if (noteId.isEmpty) return const [];
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
      items.add(
        ComposerSelectorItem(
          key: 'list:${list.id}',
          kind: ComposerSelectorItemKind.folder,
          title: list.title,
          subtitle: '${tasks.tasksForList(list.id).length} 个待办',
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
    final kind =
        map['kind']?.toString() == 'folder'
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
