import 'app_settings.dart';
import 'conversation.dart';
import 'model_config.dart';
import 'note.dart';
import 'roleplay.dart';
import 'schedule_item.dart';
import 'todo_list.dart';

enum BackupSection {
  settings,
  conversations,
  notes,
  schedules,
  todoLists,
  roleplay,
}

enum BackupSettingsPart {
  apiConfigs,
  appearance,
  conversationSettings,
  rolesAndPrompts,
}

extension BackupSettingsPartInfo on BackupSettingsPart {
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

extension BackupSectionInfo on BackupSection {
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
    }
  }

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
    }
  }
}

class BackupSelection {
  final Set<BackupSection> sections;
  final Set<BackupSettingsPart> settingsParts;
  final Set<String> conversationIds;
  final Set<String> noteIds;
  final Set<String> scheduleIds;
  final Set<String> todoListIds;
  final Set<String> roleplaySessionIds;

  const BackupSelection(
    this.sections, {
    this.settingsParts = const {},
    this.conversationIds = const {},
    this.noteIds = const {},
    this.scheduleIds = const {},
    this.todoListIds = const {},
    this.roleplaySessionIds = const {},
  });

  factory BackupSelection.all() =>
      BackupSelection(Set.of(BackupSection.values));

  factory BackupSelection.fromData(BackupData data) {
    return BackupSelection.fromDataWithSettingsParts(
      data,
      data.hasSection(BackupSection.settings)
          ? Set.of(BackupSettingsPart.values)
          : const {},
    );
  }

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
    );
  }

  bool contains(BackupSection section) => sections.contains(section);

  BackupSelection copyWith({
    Set<BackupSection>? sections,
    Set<BackupSettingsPart>? settingsParts,
    Set<String>? conversationIds,
    Set<String>? noteIds,
    Set<String>? scheduleIds,
    Set<String>? todoListIds,
    Set<String>? roleplaySessionIds,
  }) {
    return BackupSelection(
      sections ?? this.sections,
      settingsParts: settingsParts ?? this.settingsParts,
      conversationIds: conversationIds ?? this.conversationIds,
      noteIds: noteIds ?? this.noteIds,
      scheduleIds: scheduleIds ?? this.scheduleIds,
      todoListIds: todoListIds ?? this.todoListIds,
      roleplaySessionIds: roleplaySessionIds ?? this.roleplaySessionIds,
    );
  }
}

enum ImportMode { merge, addOnly, replaceSection }

extension ImportModeInfo on ImportMode {
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

enum ImportConflictAction { keepLocal, replaceLocal, keepBoth }

extension ImportConflictActionInfo on ImportConflictAction {
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

class BackupData {
  final AppSettings? appSettings;
  final List<ModelConfig>? modelConfigs;
  final List<Conversation>? conversations;
  final List<NoteFolder>? noteFolders;
  final List<Note>? notes;
  final List<Map<String, dynamic>>? notePages;
  final Map<String, String>? notePageContents;
  final List<NoteRevision>? noteRevisions;
  final List<NoteEditProposal>? noteEditProposals;
  final List<ScheduleItem>? schedules;
  final List<TodoList>? todoLists;
  final List<RoleplaySession>? roleplaySessions;

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
  });

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
        return roleplaySessions != null;
    }
  }

  Set<BackupSection> get availableSections =>
      BackupSection.values.where(hasSection).toSet();
}

class BackupArchiveData {
  final Map<String, dynamic> manifest;
  final BackupData data;
  final List<String> warnings;
  final Map<String, List<int>> assetFiles;
  final List<Map<String, dynamic>>? resources;

  const BackupArchiveData({
    required this.manifest,
    required this.data,
    this.warnings = const [],
    this.assetFiles = const {},
    this.resources,
  });

  Set<BackupSection> get availableSections => data.availableSections;
}

class ImportSectionPreview {
  final BackupSection section;
  final String detail;

  const ImportSectionPreview({required this.section, required this.detail});
}

class ImportConflict {
  final String id;
  final BackupSection section;
  final String title;
  final String localSummary;
  final String incomingSummary;

  const ImportConflict({
    required this.id,
    required this.section,
    required this.title,
    required this.localSummary,
    required this.incomingSummary,
  });
}

class BackupPreview {
  final BackupArchiveData archive;
  final List<ImportSectionPreview> sections;
  final List<ImportConflict> conflicts;
  final List<String> warnings;

  const BackupPreview({
    required this.archive,
    required this.sections,
    required this.conflicts,
    required this.warnings,
  });
}

class ImportPlan {
  final BackupSelection selection;
  final ImportMode mode;
  final Map<String, ImportConflictAction> conflictActions;

  const ImportPlan({
    required this.selection,
    required this.mode,
    this.conflictActions = const {},
  });

  Set<BackupSection> get sections => selection.sections;

  ImportConflictAction actionFor(String conflictId) {
    return conflictActions[conflictId] ?? ImportConflictAction.keepLocal;
  }
}

class ImportResult {
  final int added;
  final int replaced;
  final int skipped;
  final List<String> warnings;

  const ImportResult({
    required this.added,
    required this.replaced,
    required this.skipped,
    this.warnings = const [],
  });
}
