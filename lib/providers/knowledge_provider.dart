import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/knowledge_base.dart';
import '../models/knowledge_category.dart';
import '../models/knowledge_entry.dart';
import '../models/knowledge_explanation.dart';
import '../models/knowledge_source.dart';
import '../models/knowledge_settings.dart';
import '../repositories/knowledge_repository.dart';
import '../services/knowledge_annotation_prompt.dart';
import '../services/storage_v2_service.dart';

class KnowledgeProvider extends ChangeNotifier {
  static const defaultAnnotationRule = '标注专有名词';

  KnowledgeProvider({
    StorageV2Service? storageV2,
    KnowledgeRepository? repository,
  }) : _repository = repository ?? KnowledgeRepository(storageV2: storageV2);

  final KnowledgeRepository _repository;
  final _uuid = const Uuid();
  List<KnowledgeBase> _bases = [];
  List<KnowledgeCategory> _categories = [];
  List<KnowledgeEntry> _entries = [];
  List<KnowledgeSource> _sources = [];
  List<KnowledgeExplanation> _explanations = [];
  KnowledgeSettings _settings = KnowledgeSettings(
    updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
  );
  Future<void> _saveQueue = Future.value();
  Future<void> _pendingSave = Future.value();
  int _mutationGeneration = 0;

  List<KnowledgeBase> get knowledgeBases => List.unmodifiable(_bases);
  List<KnowledgeCategory> get categories => List.unmodifiable(_categories);
  List<KnowledgeEntry> get entries => List.unmodifiable(_entries);
  List<KnowledgeSource> get sources => List.unmodifiable(_sources);
  List<KnowledgeExplanation> get explanations =>
      List.unmodifiable(_explanations);
  KnowledgeSettings get settings => _settings;
  KnowledgeBase? get defaultKnowledgeBase =>
      _settings.defaultKnowledgeBaseId == null
      ? null
      : knowledgeBaseById(_settings.defaultKnowledgeBaseId!);

  Future<void> load() async {
    final generation = _mutationGeneration;
    await flushPendingSaves();
    final value = await _repository.load();
    if (generation != _mutationGeneration) return;
    final originalBaseId = value.settings?.defaultKnowledgeBaseId;
    final originalCategoryId = value.settings?.defaultCategoryId;
    final changedCategories = _setData(value);
    notifyListeners();
    if (changedCategories.isNotEmpty ||
        originalBaseId != _settings.defaultKnowledgeBaseId ||
        originalCategoryId != _settings.defaultCategoryId) {
      await _queueSave(
        () => _repository.saveChanges(
          upsertCategories: changedCategories,
          settings: _settings,
        ),
      );
    }
  }

  Future<void> replaceAll({
    required List<KnowledgeBase> knowledgeBases,
    required List<KnowledgeCategory> categories,
    required List<KnowledgeEntry> entries,
    required List<KnowledgeSource> sources,
    required List<KnowledgeExplanation> explanations,
    KnowledgeSettings? settings,
  }) => _runMutation(() {
    _setData(
      KnowledgeLoadResult(
        bases: knowledgeBases,
        categories: categories,
        entries: entries,
        sources: sources,
        explanations: explanations,
        settings: settings,
      ),
    );
    final replacement = KnowledgeLoadResult(
      bases: List.of(_bases),
      categories: List.of(_categories),
      entries: List.of(_entries),
      sources: List.of(_sources),
      explanations: List.of(_explanations),
      settings: _settings,
    );
    return (result: null, persist: () => _repository.replace(replacement));
  });

  KnowledgeBase? knowledgeBaseById(String id) =>
      _first(_bases, (item) => item.id == id);
  KnowledgeCategory? categoryById(String id) =>
      _first(_categories, (item) => item.id == id);
  KnowledgeCategory? categoryByAlias(String alias) =>
      _first(_categories, (item) => item.alias == alias);
  KnowledgeEntry? entryById(String id) =>
      _first(_entries, (item) => item.id == id);

  List<KnowledgeCategory> categoriesForBase(String knowledgeBaseId) =>
      List.unmodifiable(
        _categories.where((item) => item.knowledgeBaseId == knowledgeBaseId),
      );

  KnowledgeCategory? defaultCategory([String? knowledgeBaseId]) {
    final selectedId = _settings.defaultCategoryId;
    final selected = selectedId == null ? null : categoryById(selectedId);
    if (selected != null &&
        (knowledgeBaseId == null ||
            selected.knowledgeBaseId == knowledgeBaseId) &&
        _isDefaultCandidate(selected)) {
      return selected;
    }
    return _first(
      _categories,
      (item) =>
          (knowledgeBaseId == null ||
              item.knowledgeBaseId == knowledgeBaseId) &&
          _isDefaultCandidate(item),
    );
  }

  KnowledgeCategory? defaultCategoryForBase(String knowledgeBaseId) =>
      defaultCategory(knowledgeBaseId);

  List<KnowledgeCategory> get explanationCategories =>
      List.unmodifiable(_categories.where(isExplanationCategoryEnabled));

  KnowledgeCategory? get defaultExplanationCategory {
    final preferredId = _settings.defaultCategoryId;
    return _first(explanationCategories, (item) => item.id == preferredId) ??
        (explanationCategories.isEmpty ? null : explanationCategories.first);
  }

  bool isExplanationCategoryEnabled(KnowledgeCategory category) =>
      category.enabled &&
      knowledgeBaseById(category.knowledgeBaseId)?.enabled == true;

  Future<void> setDefaultKnowledgeBase(String knowledgeBaseId) async {
    final base = knowledgeBaseById(knowledgeBaseId);
    final category = _first(
      _categories,
      (item) =>
          item.knowledgeBaseId == knowledgeBaseId && _isDefaultCandidate(item),
    );
    if (base?.enabled != true || category == null) {
      throw ArgumentError.value(
        knowledgeBaseId,
        'knowledgeBaseId',
        '默认知识库必须启用且包含已启用自动标注类别',
      );
    }
    await setDefaultCategory(category.id);
  }

  Future<void> setDefaultCategory(String categoryId) => _runMutation(() {
    final category = categoryById(categoryId);
    if (category == null || !_isDefaultCandidate(category)) {
      throw ArgumentError.value(
        categoryId,
        'categoryId',
        '默认类别必须属于已启用知识库且已启用自动标注',
      );
    }
    final changed = _reconcileDefault(preferredId: categoryId);
    final savedSettings = _settings;
    return (
      result: null,
      persist: () => _repository.saveChanges(
        upsertCategories: changed,
        settings: savedSettings,
      ),
    );
  });

  KnowledgeCategory? get defaultAnnotationCategory {
    final candidates = _categories.where(_isValidAnnotationCategory);
    return _first(
          candidates,
          (item) => item.id == _settings.defaultCategoryId,
        ) ??
        (candidates.isEmpty ? null : candidates.first);
  }

  String? resolveAnnotationCategory(String alias) {
    final value = alias.trim();
    final category = _first(
      _categories,
      (item) => item.alias == value && _isValidAnnotationCategory(item),
    );
    return (category ?? defaultAnnotationCategory)?.id;
  }

  KnowledgeAnnotationPromptSnapshot get annotationPromptSnapshot =>
      KnowledgeAnnotationPromptSnapshot(
        defaultCategory: defaultAnnotationCategory?.alias ?? '',
        categories: _categories
            .where(_isValidAnnotationCategory)
            .map(
              (item) => KnowledgeAnnotationCategorySnapshot(
                category: item.alias,
                rule: item.annotationRule,
              ),
            ),
      );

  String? explanationPromptForAlias(String alias) =>
      categoryByAlias(alias)?.explanationPrompt;

  bool _isValidAnnotationCategory(KnowledgeCategory category) =>
      category.enabled &&
      category.autoAnnotate &&
      knowledgeBaseById(category.knowledgeBaseId)?.enabled == true;

  List<KnowledgeEntry> entriesForBase(String knowledgeBaseId) =>
      List.unmodifiable(
        _entries.where((item) => item.knowledgeBaseId == knowledgeBaseId),
      );
  List<KnowledgeEntry> entriesForCategory(String categoryId) =>
      List.unmodifiable(
        _entries.where((item) => item.categoryId == categoryId),
      );
  List<KnowledgeSource> sourcesForEntry(String entryId) =>
      List.unmodifiable(_sources.where((item) => item.entryId == entryId));
  List<KnowledgeExplanation> explanationsForEntry(String entryId) =>
      List.unmodifiable(_explanations.where((item) => item.entryId == entryId));

  Future<String> addKnowledgeBase({
    required String name,
    String? description,
    bool enabled = true,
  }) => _runMutation(() {
    final now = DateTime.now();
    final item = KnowledgeBase(
      id: _uuid.v4(),
      name: name,
      description: description,
      enabled: enabled,
      sortOrder: _bases.length,
      createdAt: now,
      updatedAt: now,
    );
    _bases.add(item);
    return (
      result: item.id,
      persist: () => _repository.saveChanges(upsertBases: [item]),
    );
  });

  Future<void> updateKnowledgeBase(KnowledgeBase value) async {
    final index = _bases.indexWhere((item) => item.id == value.id);
    if (index < 0) return;
    await _runMutation(() {
      final currentIndex = _bases.indexWhere((item) => item.id == value.id);
      if (currentIndex < 0) throw StateError('知识库已被删除');
      final updated = value.copyWith(
        sortOrder: _bases[currentIndex].sortOrder,
        createdAt: _bases[currentIndex].createdAt,
        updatedAt: DateTime.now(),
      );
      _bases[currentIndex] = updated;
      final changedCategories = _reconcileDefault();
      final savedSettings = _settings;
      return (
        result: null,
        persist: () => _repository.saveChanges(
          upsertBases: [updated],
          upsertCategories: changedCategories,
          settings: savedSettings,
        ),
      );
    });
  }

  Future<void> deleteKnowledgeBase(String id) async {
    if (knowledgeBaseById(id) == null) return;
    await _runMutation(() {
      final categoryIds = _categories
          .where((item) => item.knowledgeBaseId == id)
          .map((item) => item.id)
          .toSet();
      final entryIds = _entries
          .where((item) => item.knowledgeBaseId == id)
          .map((item) => item.id)
          .toSet();
      final sourceIds = _sources
          .where((item) => entryIds.contains(item.entryId))
          .map((item) => item.id)
          .toList();
      final explanationIds = _explanations
          .where((item) => entryIds.contains(item.entryId))
          .map((item) => item.id)
          .toList();
      _sources.removeWhere((item) => entryIds.contains(item.entryId));
      _explanations.removeWhere((item) => entryIds.contains(item.entryId));
      _entries.removeWhere((item) => item.knowledgeBaseId == id);
      _categories.removeWhere((item) => item.knowledgeBaseId == id);
      _bases.removeWhere((item) => item.id == id);
      _normalizeBases();
      final changedCategories = _reconcileDefault();
      final savedBases = List<KnowledgeBase>.of(_bases);
      final savedSettings = _settings;
      return (
        result: null,
        persist: () => _repository.saveChanges(
          deleteSourceIds: sourceIds,
          deleteExplanationIds: explanationIds,
          deleteEntryIds: entryIds,
          deleteCategoryIds: categoryIds,
          deleteBaseIds: [id],
          upsertBases: savedBases,
          upsertCategories: changedCategories,
          settings: savedSettings,
        ),
      );
    });
  }

  Future<String> addCategory({
    required String knowledgeBaseId,
    required String name,
    required String alias,
    String? description,
    String annotationRule = '',
    String explanationPrompt = '',
    int colorValue = 0,
    bool autoAnnotate = false,
    String? modelConfigId,
    bool isDefault = false,
    bool enabled = true,
  }) => _runMutation(() {
    _requireBase(knowledgeBaseId);
    _validateCategoryAlias(alias);
    final now = DateTime.now();
    final item = KnowledgeCategory(
      id: _uuid.v4(),
      knowledgeBaseId: knowledgeBaseId,
      name: name,
      alias: alias,
      description: description,
      annotationRule: annotationRule,
      explanationPrompt: explanationPrompt,
      colorValue: colorValue,
      autoAnnotate: autoAnnotate,
      modelConfigId: modelConfigId,
      isDefault: isDefault,
      enabled: enabled,
      sortOrder: categoriesForBase(knowledgeBaseId).length,
      createdAt: now,
      updatedAt: now,
    );
    _categories.add(item);
    final changed = _reconcileDefault(preferredId: isDefault ? item.id : null);
    if (!changed.any((value) => value.id == item.id)) {
      changed.add(categoryById(item.id)!);
    }
    final savedSettings = _settings;
    return (
      result: item.id,
      persist: () => _repository.saveChanges(
        upsertCategories: changed,
        settings: savedSettings,
      ),
    );
  });

  Future<void> updateCategory(KnowledgeCategory value) async {
    final index = _categories.indexWhere((item) => item.id == value.id);
    if (index < 0) return;
    _requireBase(value.knowledgeBaseId);
    _validateCategoryAlias(value.alias, excludingId: value.id);
    await _runMutation(() {
      final currentIndex = _categories.indexWhere(
        (item) => item.id == value.id,
      );
      if (currentIndex < 0) throw StateError('知识类别已被删除');
      _requireBase(value.knowledgeBaseId);
      _validateCategoryAlias(value.alias, excludingId: value.id);
      final previous = _categories[currentIndex];
      _categories[currentIndex] = value.copyWith(
        knowledgeBaseId: previous.knowledgeBaseId,
        annotationRule: value.annotationRule,
        sortOrder: previous.sortOrder,
        createdAt: previous.createdAt,
        updatedAt: DateTime.now(),
      );
      final changed = _reconcileDefault(
        preferredId: value.isDefault ? value.id : null,
      );
      if (!changed.any((item) => item.id == value.id)) {
        changed.add(categoryById(value.id)!);
      }
      final savedSettings = _settings;
      return (
        result: null,
        persist: () => _repository.saveChanges(
          upsertCategories: changed,
          settings: savedSettings,
        ),
      );
    });
  }

  Future<void> deleteCategory(String id) async {
    final category = categoryById(id);
    if (category == null) return;
    await _runMutation(() {
      final current = categoryById(id);
      if (current == null) throw StateError('知识类别已被删除');
      final now = DateTime.now();
      final changedEntries = <KnowledgeEntry>[];
      for (var i = 0; i < _entries.length; i++) {
        if (_entries[i].categoryId != id) continue;
        final updated = _entries[i].copyWith(categoryId: null, updatedAt: now);
        _entries[i] = updated;
        changedEntries.add(updated);
      }
      _categories.removeWhere((item) => item.id == id);
      _normalizeCategories(current.knowledgeBaseId);
      final changedCategories = _reconcileDefault();
      final normalizedCategories = categoriesForBase(
        current.knowledgeBaseId,
      ).toList();
      for (final item in changedCategories) {
        final index = normalizedCategories.indexWhere(
          (value) => value.id == item.id,
        );
        if (index < 0) {
          normalizedCategories.add(item);
        } else {
          normalizedCategories[index] = item;
        }
      }
      final savedSettings = _settings;
      return (
        result: null,
        persist: () => _repository.saveChanges(
          deleteCategoryIds: [id],
          upsertCategories: normalizedCategories,
          upsertEntries: changedEntries,
          settings: savedSettings,
        ),
      );
    });
  }

  Future<String> addEntry({
    required String knowledgeBaseId,
    String? categoryId,
    required String title,
    String content = '',
    bool enabled = true,
  }) => _runMutation(() {
    _requireEntryParents(knowledgeBaseId, categoryId);
    final now = DateTime.now();
    final item = KnowledgeEntry(
      id: _uuid.v4(),
      knowledgeBaseId: knowledgeBaseId,
      categoryId: categoryId,
      title: title,
      content: content,
      enabled: enabled,
      sortOrder: entriesForBase(knowledgeBaseId).length,
      createdAt: now,
      updatedAt: now,
    );
    _entries.add(item);
    return (
      result: item.id,
      persist: () => _repository.saveChanges(upsertEntries: [item]),
    );
  });

  Future<void> updateEntry(KnowledgeEntry value) async {
    final index = _entries.indexWhere((item) => item.id == value.id);
    if (index < 0) return;
    _requireEntryParents(value.knowledgeBaseId, value.categoryId);
    await _runMutation(() {
      final currentIndex = _entries.indexWhere((item) => item.id == value.id);
      if (currentIndex < 0) throw StateError('知识条目已被删除');
      _requireEntryParents(value.knowledgeBaseId, value.categoryId);
      final previous = _entries[currentIndex];
      final updated = value.copyWith(
        knowledgeBaseId: previous.knowledgeBaseId,
        sortOrder: previous.sortOrder,
        createdAt: previous.createdAt,
        updatedAt: DateTime.now(),
      );
      _entries[currentIndex] = updated;
      return (
        result: null,
        persist: () => _repository.saveChanges(upsertEntries: [updated]),
      );
    });
  }

  Future<void> deleteEntry(String id) async {
    if (entryById(id) == null) return;
    await _runMutation(() {
      final sourceIds = _sources
          .where((item) => item.entryId == id)
          .map((item) => item.id)
          .toList();
      final explanationIds = _explanations
          .where((item) => item.entryId == id)
          .map((item) => item.id)
          .toList();
      _sources.removeWhere((item) => item.entryId == id);
      _explanations.removeWhere((item) => item.entryId == id);
      _entries.removeWhere((item) => item.id == id);
      return (
        result: null,
        persist: () => _repository.saveChanges(
          deleteSourceIds: sourceIds,
          deleteExplanationIds: explanationIds,
          deleteEntryIds: [id],
        ),
      );
    });
  }

  Future<void> upsertSource(KnowledgeSource value) => _runMutation(() {
    _requireEntryInBase(value.entryId, value.knowledgeBaseId);
    final index = _sources.indexWhere((item) => item.id == value.id);
    final now = DateTime.now();
    final updated = value.copyWith(
      createdAt: index < 0 ? value.createdAt : _sources[index].createdAt,
      updatedAt: now,
    );
    index < 0 ? _sources.add(updated) : _sources[index] = updated;
    _sortAll();
    return (
      result: null,
      persist: () => _repository.saveChanges(upsertSources: [updated]),
    );
  });

  Future<void> deleteSource(String id) async {
    if (!_sources.any((item) => item.id == id)) return;
    await _runMutation(() {
      if (!_sources.any((item) => item.id == id)) {
        throw StateError('知识来源已被删除');
      }
      _sources.removeWhere((item) => item.id == id);
      return (
        result: null,
        persist: () => _repository.saveChanges(deleteSourceIds: [id]),
      );
    });
  }

  Future<void> upsertExplanation(KnowledgeExplanation value) => _runMutation(
    () {
      _requireEntryInBase(value.entryId, value.knowledgeBaseId);
      final index = _explanations.indexWhere((item) => item.id == value.id);
      final updated = value.copyWith(
        createdAt: index < 0 ? value.createdAt : _explanations[index].createdAt,
        updatedAt: DateTime.now(),
      );
      index < 0 ? _explanations.add(updated) : _explanations[index] = updated;
      _sortAll();
      return (
        result: null,
        persist: () => _repository.saveChanges(upsertExplanations: [updated]),
      );
    },
  );

  Future<({KnowledgeEntry entry, KnowledgeExplanation explanation})>
  saveExplanationBundle({
    required String categoryId,
    required String title,
    required String entryContent,
    required String explanation,
    required String sourceTitle,
    required String sourceUrl,
  }) => _runMutation(() {
    final category = categoryById(categoryId);
    if (category == null || !isExplanationCategoryEnabled(category)) {
      throw StateError('所选知识类别不存在或已停用');
    }
    final normalizedTitle = title.trim().toLowerCase();
    final existingEntry = _first(
      entriesForCategory(categoryId),
      (item) => item.title.trim().toLowerCase() == normalizedTitle,
    );
    if (existingEntry?.enabled == false) {
      throw StateError('同名知识条目已停用');
    }

    final now = DateTime.now();
    final entry =
        existingEntry ??
        KnowledgeEntry(
          id: _uuid.v4(),
          knowledgeBaseId: category.knowledgeBaseId,
          categoryId: category.id,
          title: title.trim(),
          content: entryContent.trim(),
          enabled: true,
          sortOrder: entriesForBase(category.knowledgeBaseId).length,
          createdAt: now,
          updatedAt: now,
        );
    final entryIndex = _entries.indexWhere((item) => item.id == entry.id);
    if (entryIndex < 0) _entries.add(entry);

    final existingSources = sourcesForEntry(entry.id);
    final normalizedUrl = sourceUrl.trim();
    final normalizedSourceTitle = sourceTitle.trim();
    final previousSource = _first(existingSources, (item) {
      if (normalizedUrl.isNotEmpty) return item.url?.trim() == normalizedUrl;
      return normalizedSourceTitle.isNotEmpty &&
          item.title.trim() == normalizedSourceTitle;
    });
    KnowledgeSource? source;
    if (normalizedUrl.isNotEmpty || normalizedSourceTitle.isNotEmpty) {
      source = KnowledgeSource(
        id: previousSource?.id ?? _uuid.v4(),
        knowledgeBaseId: category.knowledgeBaseId,
        entryId: entry.id,
        title: normalizedSourceTitle.isEmpty
            ? normalizedUrl
            : normalizedSourceTitle,
        url: normalizedUrl.isEmpty ? null : normalizedUrl,
        note: entryContent.trim().isEmpty
            ? previousSource?.note
            : entryContent.trim(),
        sortOrder: previousSource?.sortOrder ?? existingSources.length,
        createdAt: previousSource?.createdAt ?? now,
        updatedAt: now,
      );
      final sourceIndex = _sources.indexWhere((item) => item.id == source!.id);
      sourceIndex < 0 ? _sources.add(source) : _sources[sourceIndex] = source;
    }

    final existingExplanations = explanationsForEntry(entry.id);
    final previousExplanation = existingExplanations.isEmpty
        ? null
        : existingExplanations.first;
    final savedExplanation = KnowledgeExplanation(
      id: previousExplanation?.id ?? _uuid.v4(),
      knowledgeBaseId: category.knowledgeBaseId,
      entryId: entry.id,
      title: previousExplanation?.title.trim().isNotEmpty == true
          ? previousExplanation!.title
          : 'AI 释义',
      content: explanation.trim(),
      sortOrder: previousExplanation?.sortOrder ?? existingExplanations.length,
      createdAt: previousExplanation?.createdAt ?? now,
      updatedAt: now,
    );
    final explanationIndex = _explanations.indexWhere(
      (item) => item.id == savedExplanation.id,
    );
    explanationIndex < 0
        ? _explanations.add(savedExplanation)
        : _explanations[explanationIndex] = savedExplanation;
    _sortAll();
    return (
      result: (entry: entry, explanation: savedExplanation),
      persist: () => _repository.saveChanges(
        upsertEntries: existingEntry == null ? [entry] : const [],
        upsertSources: source == null ? const [] : [source],
        upsertExplanations: [savedExplanation],
      ),
    );
  });

  Future<void> deleteExplanation(String id) async {
    if (!_explanations.any((item) => item.id == id)) return;
    await _runMutation(() {
      if (!_explanations.any((item) => item.id == id)) {
        throw StateError('知识解释已被删除');
      }
      _explanations.removeWhere((item) => item.id == id);
      return (
        result: null,
        persist: () => _repository.saveChanges(deleteExplanationIds: [id]),
      );
    });
  }

  Future<void> reorderKnowledgeBases(int oldIndex, int newIndex) async {
    if (!_validMove(_bases.length, oldIndex, newIndex)) return;
    await _runMutation(() {
      if (!_validMove(_bases.length, oldIndex, newIndex)) {
        throw StateError('知识库顺序已变化');
      }
      _bases.insert(newIndex, _bases.removeAt(oldIndex));
      _normalizeBases(touch: true);
      final ordered = List<KnowledgeBase>.of(_bases);
      return (
        result: null,
        persist: () => _repository.saveChanges(upsertBases: ordered),
      );
    });
  }

  Future<void> reorderCategories(
    String baseId,
    int oldIndex,
    int newIndex,
  ) async {
    if (!_validMove(categoriesForBase(baseId).length, oldIndex, newIndex)) {
      return;
    }
    await _runMutation(() {
      final ordered = categoriesForBase(baseId).toList();
      if (!_validMove(ordered.length, oldIndex, newIndex)) {
        throw StateError('知识类别顺序已变化');
      }
      ordered.insert(newIndex, ordered.removeAt(oldIndex));
      final now = DateTime.now();
      for (var i = 0; i < ordered.length; i++) {
        final updated = ordered[i].copyWith(sortOrder: i, updatedAt: now);
        _categories[_categories.indexWhere((item) => item.id == updated.id)] =
            updated;
        ordered[i] = updated;
      }
      _sortAll();
      return (
        result: null,
        persist: () => _repository.saveChanges(upsertCategories: ordered),
      );
    });
  }

  Future<void> reorderEntries(String baseId, int oldIndex, int newIndex) async {
    if (!_validMove(entriesForBase(baseId).length, oldIndex, newIndex)) return;
    await _runMutation(() {
      final ordered = entriesForBase(baseId).toList();
      if (!_validMove(ordered.length, oldIndex, newIndex)) {
        throw StateError('知识条目顺序已变化');
      }
      ordered.insert(newIndex, ordered.removeAt(oldIndex));
      final now = DateTime.now();
      for (var i = 0; i < ordered.length; i++) {
        final updated = ordered[i].copyWith(sortOrder: i, updatedAt: now);
        _entries[_entries.indexWhere((item) => item.id == updated.id)] =
            updated;
        ordered[i] = updated;
      }
      _sortAll();
      return (
        result: null,
        persist: () => _repository.saveChanges(upsertEntries: ordered),
      );
    });
  }

  Future<void> flushPendingSaves() => _pendingSave;

  Future<T> _runMutation<T>(
    ({T result, Future<void> Function() persist}) Function() mutate,
  ) {
    final next = _saveQueue.then<T>((_) async {
      final snapshot = _KnowledgeMutationSnapshot.capture(this);
      final generation = ++_mutationGeneration;
      try {
        final mutation = mutate();
        notifyListeners();
        await mutation.persist();
        return mutation.result;
      } catch (error, stackTrace) {
        if (_mutationGeneration == generation) {
          snapshot.restore(this);
          notifyListeners();
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    });
    _saveQueue = next.then<void>((_) {}).catchError((Object _) {});
    _pendingSave = _saveQueue;
    return next;
  }

  List<KnowledgeCategory> _setData(KnowledgeLoadResult value) {
    _bases = List.of(value.bases);
    _settings =
        value.settings ??
        KnowledgeSettings(
          updatedAt: DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        );
    final baseIds = _bases.map((item) => item.id).toSet();
    _categories = value.categories
        .where((item) => baseIds.contains(item.knowledgeBaseId))
        .toList();
    final aliases = <String>{};
    for (final category in _categories) {
      if (!aliases.add(category.alias)) {
        throw StateError('知识类别 alias 重复: ${category.alias}');
      }
    }
    final categoryIds = _categories.map((item) => item.id).toSet();
    _entries = value.entries
        .where((item) => baseIds.contains(item.knowledgeBaseId))
        .map(
          (item) =>
              item.categoryId == null || categoryIds.contains(item.categoryId)
              ? item
              : item.copyWith(categoryId: null),
        )
        .toList();
    final entryIds = _entries.map((item) => item.id).toSet();
    _sources = value.sources
        .where(
          (item) =>
              entryIds.contains(item.entryId) &&
              entryById(item.entryId)?.knowledgeBaseId == item.knowledgeBaseId,
        )
        .toList();
    _explanations = value.explanations
        .where(
          (item) =>
              entryIds.contains(item.entryId) &&
              entryById(item.entryId)?.knowledgeBaseId == item.knowledgeBaseId,
        )
        .toList();
    _sortAll();
    return _reconcileDefault(
      preferredId: _settings.defaultCategoryId,
      legacyPreferredId: value.settings == null
          ? _first(_categories, (item) => item.isDefault)?.id
          : null,
    );
  }

  List<KnowledgeCategory> _reconcileDefault({
    String? preferredId,
    String? legacyPreferredId,
  }) {
    final preferred = preferredId == null ? null : categoryById(preferredId);
    final legacy = legacyPreferredId == null
        ? null
        : categoryById(legacyPreferredId);
    final selected =
        (preferred != null && _isDefaultCandidate(preferred)
            ? preferred.id
            : null) ??
        (legacy != null && _isDefaultCandidate(legacy) ? legacy.id : null) ??
        _first(_categories, _isDefaultCandidate)?.id;
    final selectedCategory = selected == null ? null : categoryById(selected);
    final selectedBaseId = selectedCategory?.knowledgeBaseId;
    if (_settings.defaultKnowledgeBaseId != selectedBaseId ||
        _settings.defaultCategoryId != selectedCategory?.id) {
      _settings = KnowledgeSettings(
        defaultKnowledgeBaseId: selectedBaseId,
        defaultCategoryId: selectedCategory?.id,
        updatedAt: DateTime.now().toUtc(),
      );
    }
    final changed = <KnowledgeCategory>[];
    for (final item in List<KnowledgeCategory>.of(_categories)) {
      final isDefault = item.id == selected;
      final next = item.copyWith(isDefault: isDefault);
      final index = _categories.indexWhere((value) => value.id == item.id);
      if (next.isDefault != item.isDefault) {
        changed.add(next);
      }
      _categories[index] = next;
    }
    if (changed.isEmpty && preferredId != null) {
      final item = categoryById(preferredId);
      if (item != null) changed.add(item);
    }
    return changed;
  }

  bool _isDefaultCandidate(KnowledgeCategory category) =>
      category.enabled &&
      category.autoAnnotate &&
      knowledgeBaseById(category.knowledgeBaseId)?.enabled == true;

  void _normalizeBases({bool touch = false}) {
    final now = DateTime.now();
    for (var i = 0; i < _bases.length; i++) {
      _bases[i] = _bases[i].copyWith(
        sortOrder: i,
        updatedAt: touch ? now : _bases[i].updatedAt,
      );
    }
  }

  void _normalizeCategories(String baseId) {
    final items = categoriesForBase(baseId).toList();
    for (var i = 0; i < items.length; i++) {
      final updated = items[i].copyWith(
        sortOrder: i,
        updatedAt: DateTime.now(),
      );
      _categories[_categories.indexWhere((item) => item.id == updated.id)] =
          updated;
    }
    _sortAll();
  }

  void _sortAll() {
    int compare(dynamic a, dynamic b) => a.sortOrder.compareTo(b.sortOrder);
    _bases.sort(compare);
    _categories.sort(
      (a, b) => a.knowledgeBaseId == b.knowledgeBaseId
          ? compare(a, b)
          : a.knowledgeBaseId.compareTo(b.knowledgeBaseId),
    );
    _entries.sort(
      (a, b) => a.knowledgeBaseId == b.knowledgeBaseId
          ? compare(a, b)
          : a.knowledgeBaseId.compareTo(b.knowledgeBaseId),
    );
    _sources.sort(
      (a, b) => a.entryId == b.entryId
          ? compare(a, b)
          : a.entryId.compareTo(b.entryId),
    );
    _explanations.sort(
      (a, b) => a.entryId == b.entryId
          ? compare(a, b)
          : a.entryId.compareTo(b.entryId),
    );
  }

  void _requireBase(String id) {
    if (knowledgeBaseById(id) == null) {
      throw ArgumentError.value(id, 'knowledgeBaseId', '知识库不存在');
    }
  }

  void _validateCategoryAlias(String alias, {String? excludingId}) {
    if (!isValidKnowledgeCategoryAlias(alias)) {
      throw ArgumentError.value(alias, 'alias', '类别别名格式无效');
    }
    final existing = categoryByAlias(alias);
    if (existing != null && existing.id != excludingId) {
      throw ArgumentError.value(alias, 'alias', '类别别名已存在');
    }
  }

  void _requireEntryInBase(String entryId, String knowledgeBaseId) {
    _requireBase(knowledgeBaseId);
    final entry = entryById(entryId);
    if (entry == null || entry.knowledgeBaseId != knowledgeBaseId) {
      throw ArgumentError.value(entryId, 'entryId', '知识条目不存在或不属于该知识库');
    }
  }

  void _requireEntryParents(String baseId, String? categoryId) {
    _requireBase(baseId);
    if (categoryId == null) return;
    final category = categoryById(categoryId);
    if (category == null || category.knowledgeBaseId != baseId) {
      throw ArgumentError.value(categoryId, 'categoryId', '知识类别不存在或不属于该知识库');
    }
  }

  Future<void> _queueSave(Future<void> Function() operation) {
    final next = _saveQueue.then((_) => operation());
    _saveQueue = next.catchError((Object _) {});
    _pendingSave = next;
    return next;
  }
}

final class _KnowledgeMutationSnapshot {
  _KnowledgeMutationSnapshot({
    required this.bases,
    required this.categories,
    required this.entries,
    required this.sources,
    required this.explanations,
    required this.settings,
    required this.generation,
  });

  factory _KnowledgeMutationSnapshot.capture(KnowledgeProvider provider) =>
      _KnowledgeMutationSnapshot(
        bases: List.of(provider._bases),
        categories: List.of(provider._categories),
        entries: List.of(provider._entries),
        sources: List.of(provider._sources),
        explanations: List.of(provider._explanations),
        settings: provider._settings,
        generation: provider._mutationGeneration,
      );

  final List<KnowledgeBase> bases;
  final List<KnowledgeCategory> categories;
  final List<KnowledgeEntry> entries;
  final List<KnowledgeSource> sources;
  final List<KnowledgeExplanation> explanations;
  final KnowledgeSettings settings;
  final int generation;

  void restore(KnowledgeProvider provider) {
    provider._bases = List.of(bases);
    provider._categories = List.of(categories);
    provider._entries = List.of(entries);
    provider._sources = List.of(sources);
    provider._explanations = List.of(explanations);
    provider._settings = settings;
    provider._mutationGeneration = generation;
  }
}

T? _first<T>(Iterable<T> values, bool Function(T) matches) {
  for (final value in values) {
    if (matches(value)) return value;
  }
  return null;
}

bool _validMove(int length, int oldIndex, int newIndex) =>
    oldIndex >= 0 && oldIndex < length && newIndex >= 0 && newIndex < length;
