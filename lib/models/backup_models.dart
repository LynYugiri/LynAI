import 'app_settings.dart';
import 'conversation.dart';
import 'model_config.dart';
import 'note.dart';
import 'plugin.dart';
import 'roleplay.dart';
import 'schedule_item.dart';
import 'todo_list.dart';

/// 备份数据的分类。
///
/// 每个分类对应一组可独立选择和恢复的应用数据。
enum BackupSection {
  /// 应用设置。
  settings,

  /// 对话记录。
  conversations,

  /// 笔记。
  notes,

  /// 日程。
  schedules,

  /// 待办清单。
  todoLists,

  /// 情景演绎。
  roleplay,

  /// 插件。
  plugins,
}

/// 设置备份的子分类。
///
/// 将设置数据细分为可独立选择的子部分。
enum BackupSettingsPart {
  /// API 配置。
  apiConfigs,

  /// 外观设置。
  appearance,

  /// 对话设置。
  conversationSettings,

  /// 角色与提示词。
  rolesAndPrompts,
}

/// [BackupSettingsPart] 的扩展信息，提供子分类的显示标签。
extension BackupSettingsPartInfo on BackupSettingsPart {
  /// 子分类的中文显示标签。
  String get label {
    switch (this) {
      case BackupSettingsPart.apiConfigs:
        return 'API 配置';
      case BackupSettingsPart.appearance:
        return '外观设置';
      case BackupSettingsPart.conversationSettings:
        return '对话设置';
      case BackupSettingsPart.rolesAndPrompts:
        return '角色与提示词';
    }
  }
}

/// [BackupSection] 的扩展信息，提供分类的键名和显示标签。
extension BackupSectionInfo on BackupSection {
  /// 分类在备份文件中的键名。
  String get key {
    switch (this) {
      case BackupSection.settings:
        return 'settings';
      case BackupSection.conversations:
        return 'conversations';
      case BackupSection.notes:
        return 'notes';
      case BackupSection.schedules:
        return 'schedules';
      case BackupSection.todoLists:
        return 'todoLists';
      case BackupSection.roleplay:
        return 'roleplay';
      case BackupSection.plugins:
        return 'plugins';
    }
  }

  /// 分类的中文显示标签。
  String get label {
    switch (this) {
      case BackupSection.settings:
        return '设置';
      case BackupSection.conversations:
        return '对话记录';
      case BackupSection.notes:
        return '笔记';
      case BackupSection.schedules:
        return '日程';
      case BackupSection.todoLists:
        return '待办清单';
      case BackupSection.roleplay:
        return '情景演绎';
      case BackupSection.plugins:
        return '插件';
    }
  }
}

/// 备份导出或导入时的选择范围。
///
/// 定义哪些分类、子分类和具体 ID 的数据需要被导出或导入。
class BackupSelection {
  /// 选中的数据分类集合。
  final Set<BackupSection> sections;

  /// 选中的设置子分类集合。
  final Set<BackupSettingsPart> settingsParts;

  /// 选中的对话 ID 集合。
  final Set<String> conversationIds;

  /// 选中的笔记 ID 集合。
  final Set<String> noteIds;

  /// 选中的日程 ID 集合。
  final Set<String> scheduleIds;

  /// 选中的待办清单 ID 集合。
  final Set<String> todoListIds;

  /// 选中的情景演绎会话 ID 集合。
  final Set<String> roleplaySessionIds;

  /// 选中的插件 ID 集合。
  final Set<String> pluginIds;

  /// 创建一个备份选择范围实例。
  const BackupSelection(
    this.sections, {
    this.settingsParts = const {},
    this.conversationIds = const {},
    this.noteIds = const {},
    this.scheduleIds = const {},
    this.todoListIds = const {},
    this.roleplaySessionIds = const {},
    this.pluginIds = const {},
  });

  /// 创建一个全选所有分类的备份选择范围。
  factory BackupSelection.all() =>
      BackupSelection(Set.of(BackupSection.values));

  /// 根据备份数据自动创建选择范围，全选所有可用分类和设置子分类。
  factory BackupSelection.fromData(BackupData data) {
    return BackupSelection.fromDataWithSettingsParts(
      data,
      data.hasSection(BackupSection.settings)
          ? Set.of(BackupSettingsPart.values)
          : const {},
    );
  }

  /// 根据备份数据创建选择范围，并指定设置子分类。
  factory BackupSelection.fromDataWithSettingsParts(
    BackupData data,
    Set<BackupSettingsPart> settingsParts,
  ) {
    final sections = Set<BackupSection>.from(data.availableSections);
    if (settingsParts.isEmpty) sections.remove(BackupSection.settings);
    return BackupSelection(
      sections,
      settingsParts: settingsParts,
      conversationIds:
          data.conversations?.map((item) => item.id).toSet() ?? const {},
      noteIds: data.notes?.map((item) => item.id).toSet() ?? const {},
      scheduleIds: data.schedules?.map((item) => item.id).toSet() ?? const {},
      todoListIds: data.todoLists?.map((item) => item.id).toSet() ?? const {},
      roleplaySessionIds:
          data.roleplaySessions?.map((item) => item.id).toSet() ?? const {},
      pluginIds:
          data.plugins?.map((item) => item.plugin.id).toSet() ?? const {},
    );
  }

  /// 判断指定分类是否在选中范围内。
  bool contains(BackupSection section) => sections.contains(section);

  /// 创建当前实例的副本，可选择性更新部分字段。
  BackupSelection copyWith({
    Set<BackupSection>? sections,
    Set<BackupSettingsPart>? settingsParts,
    Set<String>? conversationIds,
    Set<String>? noteIds,
    Set<String>? scheduleIds,
    Set<String>? todoListIds,
    Set<String>? roleplaySessionIds,
    Set<String>? pluginIds,
  }) {
    return BackupSelection(
      sections ?? this.sections,
      settingsParts: settingsParts ?? this.settingsParts,
      conversationIds: conversationIds ?? this.conversationIds,
      noteIds: noteIds ?? this.noteIds,
      scheduleIds: scheduleIds ?? this.scheduleIds,
      todoListIds: todoListIds ?? this.todoListIds,
      roleplaySessionIds: roleplaySessionIds ?? this.roleplaySessionIds,
      pluginIds: pluginIds ?? this.pluginIds,
    );
  }
}

/// 单个插件的备份载荷。
class BackupPluginData {
  /// 插件安装状态和清单。
  final InstalledPlugin plugin;

  /// 插件用户设置。
  final Map<String, dynamic> settings;

  /// 插件私有 storage。
  final Map<String, dynamic> storage;

  /// 插件目录内的文件列表。
  final List<BackupPluginFile> files;

  /// 创建插件备份载荷。
  const BackupPluginData({
    required this.plugin,
    this.settings = const {},
    this.storage = const {},
    this.files = const [],
  });

  /// 从 JSON 创建插件备份载荷。
  factory BackupPluginData.fromJson(Map<String, dynamic> json) {
    return BackupPluginData(
      plugin: InstalledPlugin.fromJson(
        Map<String, dynamic>.from(json['plugin'] as Map? ?? const {}),
      ),
      settings: Map<String, dynamic>.from(json['settings'] as Map? ?? const {}),
      storage: Map<String, dynamic>.from(json['storage'] as Map? ?? const {}),
      files: (json['files'] as List<dynamic>? ?? const [])
          .whereType<Map>()
          .map(
            (item) =>
                BackupPluginFile.fromJson(Map<String, dynamic>.from(item)),
          )
          .toList(growable: false),
    );
  }

  /// 转成 JSON。
  Map<String, dynamic> toJson() => {
    'plugin': plugin.toJson(),
    'settings': settings,
    'storage': storage,
    'files': files.map((item) => item.toJson()).toList(),
  };
}

/// 插件目录内的一个备份文件。
class BackupPluginFile {
  /// 插件相对路径。
  final String path;

  /// 备份包内路径。
  final String archivePath;

  /// 创建插件文件备份记录。
  const BackupPluginFile({required this.path, required this.archivePath});

  /// 从 JSON 创建插件文件备份记录。
  factory BackupPluginFile.fromJson(Map<String, dynamic> json) {
    return BackupPluginFile(
      path: json['path'] as String? ?? '',
      archivePath: json['archivePath'] as String? ?? '',
    );
  }

  /// 转成 JSON。
  Map<String, dynamic> toJson() => {'path': path, 'archivePath': archivePath};
}

/// 备份导入时的合并模式。
enum ImportMode {
  /// 合并数据，遇到冲突时询问用户。
  merge,

  /// 只添加本地不存在的条目，跳过所有冲突。
  addOnly,

  /// 用导入数据完全替换所选分类。
  replaceSection,
}

/// [ImportMode] 的扩展信息，提供合并模式的中文标签。
extension ImportModeInfo on ImportMode {
  /// 合并模式的中文显示标签。
  String get label {
    switch (this) {
      case ImportMode.merge:
        return '合并，冲突时询问';
      case ImportMode.addOnly:
        return '只添加新数据，跳过冲突';
      case ImportMode.replaceSection:
        return '替换所选分类';
    }
  }
}

/// 导入过程中遇到 ID 冲突时的处理动作。
enum ImportConflictAction {
  /// 保留本地数据。
  keepLocal,

  /// 使用导入数据替换本地。
  replaceLocal,

  /// 同时保留两份数据。
  keepBoth,
}

/// [ImportConflictAction] 的扩展信息，提供冲突处理动作的中文标签。
extension ImportConflictActionInfo on ImportConflictAction {
  /// 冲突处理动作的中文显示标签。
  String get label {
    switch (this) {
      case ImportConflictAction.keepLocal:
        return '保留本地';
      case ImportConflictAction.replaceLocal:
        return '使用导入';
      case ImportConflictAction.keepBoth:
        return '两者保留';
    }
  }
}

/// 备份数据的完整载荷。
///
/// 各字段按分类分组，为 null 的分类表示不在本次备份中。
class BackupData {
  /// 应用全局设置。
  final AppSettings? appSettings;

  /// 模型配置列表。
  final List<ModelConfig>? modelConfigs;

  /// 对话记录列表。
  final List<Conversation>? conversations;

  /// 笔记文件夹列表。
  final List<NoteFolder>? noteFolders;

  /// 笔记列表。
  final List<Note>? notes;

  /// 笔记页面列表。
  final List<Map<String, dynamic>>? notePages;

  /// 笔记页面内容映射，key 为页面 ID。
  final Map<String, String>? notePageContents;

  /// 笔记修订记录列表。
  final List<NoteRevision>? noteRevisions;

  /// 笔记编辑建议列表。
  final List<NoteEditProposal>? noteEditProposals;

  /// 日程列表。
  final List<ScheduleItem>? schedules;

  /// 待办清单列表。
  final List<TodoList>? todoLists;

  /// 情景演绎场景模板列表。
  final List<RoleplayScenario>? roleplaySessions;

  /// 情景演绎会话列表。
  final List<RoleplayThread>? roleplayThreads;

  /// 插件列表。
  final List<BackupPluginData>? plugins;

  /// 创建一个备份数据实例。
  const BackupData({
    this.appSettings,
    this.modelConfigs,
    this.conversations,
    this.noteFolders,
    this.notes,
    this.notePages,
    this.notePageContents,
    this.noteRevisions,
    this.noteEditProposals,
    this.schedules,
    this.todoLists,
    this.roleplaySessions,
    this.roleplayThreads,
    this.plugins,
  });

  /// 判断指定分类是否有可用的备份数据。
  bool hasSection(BackupSection section) {
    switch (section) {
      case BackupSection.settings:
        return appSettings != null || modelConfigs != null;
      case BackupSection.conversations:
        return conversations != null;
      case BackupSection.notes:
        return noteFolders != null ||
            notes != null ||
            notePages != null ||
            noteRevisions != null ||
            noteEditProposals != null;
      case BackupSection.schedules:
        return schedules != null;
      case BackupSection.todoLists:
        return todoLists != null;
      case BackupSection.roleplay:
        return roleplaySessions != null || roleplayThreads != null;
      case BackupSection.plugins:
        return plugins != null;
    }
  }

  /// 获取所有含数据的分类集合。
  Set<BackupSection> get availableSections =>
      BackupSection.values.where(hasSection).toSet();
}

/// 从备份归档文件中解析出的数据。
///
/// 包含清单信息、备份数据和归档元信息。
class BackupArchiveData {
  /// 备份归档的清单信息。
  final Map<String, dynamic> manifest;

  /// 备份的核心数据载荷。
  final BackupData data;

  /// 解析过程中产生的警告信息列表。
  final List<String> warnings;

  /// 归档中包含的资源文件映射，key 为文件路径。
  final Map<String, List<int>> assetFiles;

  /// 归档中的附加资源列表。
  final List<Map<String, dynamic>>? resources;

  /// 归档中的插件文件映射，key 为备份包内路径。
  final Map<String, List<int>> pluginFiles;

  /// 创建一个备份归档数据实例。
  const BackupArchiveData({
    required this.manifest,
    required this.data,
    this.warnings = const [],
    this.assetFiles = const {},
    this.resources,
    this.pluginFiles = const {},
  });

  /// 获取归档中所有含数据的分类集合。
  Set<BackupSection> get availableSections => data.availableSections;
}

/// 导入前的分类预览信息。
///
/// 在确认导入前展示每个分类将导入的数据概要。
class ImportSectionPreview {
  /// 对应的备份分类。
  final BackupSection section;

  /// 分类的数据概要描述。
  final String detail;

  /// 创建一个导入分类预览实例。
  const ImportSectionPreview({required this.section, required this.detail});
}

/// 导入过程中检测到的 ID 冲突条目。
///
/// 当本地和导入数据中存在相同 ID 但内容不同的条目时生成冲突记录。
class ImportConflict {
  /// 冲突条目 ID。
  final String id;

  /// 冲突所属的备份分类。
  final BackupSection section;

  /// 冲突条目标题。
  final String title;

  /// 本地数据摘要。
  final String localSummary;

  /// 导入数据摘要。
  final String incomingSummary;

  /// 创建一个导入冲突实例。
  const ImportConflict({
    required this.id,
    required this.section,
    required this.title,
    required this.localSummary,
    required this.incomingSummary,
  });
}

/// 导入前的完整预览结果。
///
/// 包含归档数据、各分类预览、冲突列表和警告信息。
class BackupPreview {
  /// 备份归档数据。
  final BackupArchiveData archive;

  /// 各分类的导入预览列表。
  final List<ImportSectionPreview> sections;

  /// 检测到的冲突条目列表。
  final List<ImportConflict> conflicts;

  /// 预览过程中产生的警告信息列表。
  final List<String> warnings;

  /// 创建一个备份预览实例。
  const BackupPreview({
    required this.archive,
    required this.sections,
    required this.conflicts,
    required this.warnings,
  });
}

/// 用户确认的导入执行计划。
///
/// 包含选择范围、合并模式和每个冲突的处理策略。
class ImportPlan {
  /// 导入选择范围。
  final BackupSelection selection;

  /// 导入合并模式。
  final ImportMode mode;

  /// 各冲突条目的处理动作映射。
  final Map<String, ImportConflictAction> conflictActions;

  /// 创建一个导入计划实例。
  const ImportPlan({
    required this.selection,
    required this.mode,
    this.conflictActions = const {},
  });

  /// 获取计划中导入的分类集合。
  Set<BackupSection> get sections => selection.sections;

  /// 获取指定冲突 ID 的处理动作，默认为保留本地。
  ImportConflictAction actionFor(String conflictId) {
    return conflictActions[conflictId] ?? ImportConflictAction.keepLocal;
  }
}

/// 导入完成后的结果统计。
class ImportResult {
  /// 新增的条目数量。
  final int added;

  /// 被替换的条目数量。
  final int replaced;

  /// 被跳过的条目数量。
  final int skipped;

  /// 导入过程中产生的警告信息列表。
  final List<String> warnings;

  /// 创建一个导入结果实例。
  const ImportResult({
    required this.added,
    required this.replaced,
    required this.skipped,
    this.warnings = const [],
  });
}
