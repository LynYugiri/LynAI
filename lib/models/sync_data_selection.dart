enum SyncDataCategory {
  conversations,
  notes,
  tasks,
  knowledge,
  calendar,
  roleplay,
  settings,
  models,
  plugins,
  staticResources,
}

class SyncDataSelection {
  const SyncDataSelection(this.categories);

  final Set<SyncDataCategory> categories;

  static const defaults = SyncDataSelection({
    SyncDataCategory.conversations,
    SyncDataCategory.notes,
    SyncDataCategory.tasks,
    SyncDataCategory.knowledge,
    SyncDataCategory.calendar,
    SyncDataCategory.roleplay,
    SyncDataCategory.settings,
    SyncDataCategory.models,
    SyncDataCategory.plugins,
  });

  static const all = SyncDataSelection({...SyncDataCategory.values});

  bool contains(SyncDataCategory category) => categories.contains(category);

  bool isSubsetOf(SyncDataSelection other) =>
      other.categories.containsAll(categories);

  bool hasSameCategories(SyncDataSelection other) =>
      categories.length == other.categories.length && isSubsetOf(other);

  SyncDataSelection intersect(SyncDataSelection other) => SyncDataSelection(
    Set.unmodifiable(categories.intersection(other.categories)),
  );

  SyncDataSelection union(SyncDataSelection other) =>
      SyncDataSelection(Set.unmodifiable(categories.union(other.categories)));

  SyncDataSelection copyWithCategory(
    SyncDataCategory category, {
    required bool enabled,
  }) {
    final next = Set<SyncDataCategory>.of(categories);
    enabled ? next.add(category) : next.remove(category);
    return SyncDataSelection(Set.unmodifiable(next));
  }

  List<String> toJson() => categories.map((item) => item.name).toList()..sort();

  factory SyncDataSelection.fromJson(Object? value) {
    if (value is! List) return defaults;
    final categories = <SyncDataCategory>{};
    for (final item in value.whereType<String>()) {
      for (final category in SyncDataCategory.values) {
        if (category.name == item) categories.add(category);
      }
    }
    return SyncDataSelection(Set.unmodifiable(categories));
  }
}

class SyncDataRegistry {
  const SyncDataRegistry._();

  static SyncDataCategory? categoryForChange(
    String table,
    Map<String, dynamic>? data,
  ) => switch (table) {
    'conversations' ||
    'messages' ||
    'message_attachments' => SyncDataCategory.conversations,
    'note_folders' ||
    'notes' ||
    'note_pages' ||
    'note_revisions' ||
    'note_page_heads' ||
    'note_page_tombstones' => SyncDataCategory.notes,
    'tasks' || 'task_lists' || 'task_list_entries' => SyncDataCategory.tasks,
    'knowledge_bases' ||
    'knowledge_categories' ||
    'knowledge_entries' ||
    'knowledge_sources' ||
    'knowledge_explanations' => SyncDataCategory.knowledge,
    'calendar_events' || 'anniversaries' => SyncDataCategory.calendar,
    'roleplay_scenarios' || 'roleplay_threads' => SyncDataCategory.roleplay,
    'shared_settings' => SyncDataCategory.settings,
    'synced_model_configs' => SyncDataCategory.models,
    'plugin_files' ||
    'plugin_settings' ||
    'plugin_config' => SyncDataCategory.plugins,
    'resources' => _resourceOwner(data?['role']),
    'recycle_bin' => _recycleBinOwner(data),
    _ => null,
  };

  static bool allowsChange(
    SyncDataSelection selection,
    String table,
    Map<String, dynamic>? data,
  ) {
    if (table == 'recycle_bin' && data == null) return true;
    if (table == 'resources' && data == null) {
      return selection.contains(SyncDataCategory.staticResources);
    }
    final category = categoryForChange(table, data);
    if (category == null || !selection.contains(category)) return false;
    return table != 'resources' ||
        selection.contains(SyncDataCategory.staticResources);
  }

  static Map<String, dynamic>? selectionData(
    Map<String, dynamic>? data,
    Map<String, dynamic>? localHint,
  ) => data ?? localHint;

  static SyncDataCategory? _resourceOwner(Object? role) => switch (role) {
    'message_attachment' || 'message_image' => SyncDataCategory.conversations,
    'background' => SyncDataCategory.settings,
    _ => null,
  };

  static SyncDataCategory? _recycleBinOwner(Map<String, dynamic>? data) {
    final type = data?['type'];
    final byType = switch (type) {
      'conversation' => SyncDataCategory.conversations,
      'note' || 'notePage' => SyncDataCategory.notes,
      'task' || 'taskList' || 'todoList' => SyncDataCategory.tasks,
      'calendarEvent' || 'anniversary' => SyncDataCategory.calendar,
      'roleplayScenario' || 'roleplayThread' => SyncDataCategory.roleplay,
      'plugin.data' || 'plugin.file' => SyncDataCategory.plugins,
      _ => null,
    };
    if (byType != null) return byType;
    final category = data?['category'];
    return switch (category) {
      'conversation' ||
      'conversations' ||
      'message' => SyncDataCategory.conversations,
      'note' || 'notes' => SyncDataCategory.notes,
      'task' || 'tasks' || 'taskList' || 'todos' => SyncDataCategory.tasks,
      'calendar' ||
      'event' ||
      'anniversary' ||
      'schedules' => SyncDataCategory.calendar,
      'roleplay' || 'roleplayScenario' => SyncDataCategory.roleplay,
      String value when value.startsWith('plugin:') => SyncDataCategory.plugins,
      _ => null,
    };
  }
}
