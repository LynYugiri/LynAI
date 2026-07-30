import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/knowledge_base.dart';
import '../models/knowledge_category.dart';
import '../models/knowledge_entry.dart';
import '../models/knowledge_explanation.dart';
import '../models/knowledge_source.dart';
import '../repositories/knowledge_repository.dart';
import '../services/knowledge_annotation_prompt.dart';
import '../services/storage_v2_service.dart';

class KnowledgeProvider extends ChangeNotifier {
  static const builtInProperNounKnowledgeBaseId =
      builtInProperNounKnowledgeBaseModelId;
  static const builtInProperNounCategoryId =
      builtInProperNounCategoryModelId;
  static const properNounAlias = properNounKnowledgeCategoryAlias;
  static const defaultAnnotationRule = '标注专有名词';
  static final builtInInitialTime = DateTime.utc(2026, 7, 30);

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
  Future<void> _saveQueue = Future.value();
  Future<void> _pendingSave = Future.value();
  int _mutationGeneration = 0;

  List<KnowledgeBase> get knowledgeBases => List.unmodifiable(_bases);
  List<KnowledgeCategory> get categories => List.unmodifiable(_categories);
  List<KnowledgeEntry> get entries => List.unmodifiable(_entries);
  List<KnowledgeSource> get sources => List.unmodifiable(_sources);
  List<KnowledgeExplanation> get explanations =>
      List.unmodifiable(_explanations);

  Future<void> load() async {
    final generation = _mutationGeneration;
    await flushPendingSaves();
    final value = await _repository.load();
    if (generation != _mutationGeneration) return;
    final snapshot = _KnowledgeMutationSnapshot.capture(this);
    final normalized = _setData(value);
    notifyListeners();
    if (normalized.changed) {
      try {
        await _queueSave(() => _repository.replace(normalized.value));
      } catch (error, stackTrace) {
        if (_mutationGeneration == generation) {
          snapshot.restore(this);
          notifyListeners();
        }
        Error.throwWithStackTrace(error, stackTrace);
      }
    }
  }

  Future<void> replaceAll({
    required List<KnowledgeBase> knowledgeBases,
    required List<KnowledgeCategory> categories,
    required List<KnowledgeEntry> entries,
    required List<KnowledgeSource> sources,
    required List<KnowledgeExplanation> explanations,
  }) => _runMutation(() {
    _setData(
      KnowledgeLoadResult(
        bases: knowledgeBases,
        categories: categories,
        entries: entries,
        sources: sources,
        explanations: explanations,
      ),
    );
    final replacement = KnowledgeLoadResult(
      bases: List.of(_bases),
      categories: List.of(_categories),
      entries: List.of(_entries),
      sources: List.of(_sources),
      explanations: List.of(_explanations),
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

  List<KnowledgeCategory> get explanationCategories =>
      List.unmodifiable(_categories.where(isExplanationCategoryEnabled));

  KnowledgeCategory? get defaultExplanationCategory {
    return _first(
          explanationCategories,
          (item) => item.id == builtInProperNounCategoryId,
        ) ??
        (explanationCategories.isEmpty ? null : explanationCategories.first);
  }

  bool isExplanationCategoryEnabled(KnowledgeCategory category) =>
      category.enabled &&
      knowledgeBaseById(category.knowledgeBaseId)?.enabled == true;

  KnowledgeCategory? get annotationFallbackCategory {
    final category = categoryById(builtInProperNounCategoryId);
    return category != null && _isValidAnnotationCategory(category)
        ? category
        : null;
  }

  String? resolveAnnotationCategory(String alias) {
    final value = alias.trim();
    final category = _first(
      _categories,
      (item) => item.alias == value && _isValidAnnotationCategory(item),
    );
    return (category ?? annotationFallbackCategory)?.id;
  }

  KnowledgeAnnotationPromptSnapshot get knowledgeAnnotationPromptSnapshot =>
      KnowledgeAnnotationPromptSnapshot(
        fallbackCategory: annotationFallbackCategory?.alias ?? '',
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
      return (
        result: null,
        persist: () => _repository.saveChanges(upsertBases: [updated]),
      );
    });
  }

  Future<void> deleteKnowledgeBase(String id) async {
    if (id == builtInProperNounKnowledgeBaseId) {
      throw ArgumentError.value(id, 'id', '内置知识库不可删除');
    }
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
      final savedBases = List<KnowledgeBase>.of(_bases);
      return (
        result: null,
        persist: () => _repository.saveChanges(
          deleteSourceIds: sourceIds,
          deleteExplanationIds: explanationIds,
          deleteEntryIds: entryIds,
          deleteCategoryIds: categoryIds,
          deleteBaseIds: [id],
          upsertBases: savedBases,
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
      enabled: enabled,
      sortOrder: categoriesForBase(knowledgeBaseId).length,
      createdAt: now,
      updatedAt: now,
    );
    _categories.add(item);
    return (
      result: item.id,
      persist: () => _repository.saveChanges(upsertCategories: [item]),
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
      final updated = _categories[currentIndex];
      return (
        result: null,
        persist: () => _repository.saveChanges(upsertCategories: [updated]),
      );
    });
  }

  Future<void> deleteCategory(String id) async {
    if (id == builtInProperNounCategoryId) {
      throw ArgumentError.value(id, 'id', '内置类别不可删除');
    }
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
      final normalizedCategories = categoriesForBase(
        current.knowledgeBaseId,
      ).toList();
      return (
        result: null,
        persist: () => _repository.saveChanges(
          deleteCategoryIds: [id],
          upsertCategories: normalizedCategories,
          upsertEntries: changedEntries,
        ),
      );
    });
  }

  bool isBuiltInKnowledgeBase(KnowledgeBase value) =>
      value.id == builtInProperNounKnowledgeBaseId;

  bool isBuiltInCategory(KnowledgeCategory value) =>
      value.id == builtInProperNounCategoryId;

  Future<void> restoreBuiltInKnowledgeBase() => _runMutation(() {
    final index = _bases.indexWhere(
      (item) => item.id == builtInProperNounKnowledgeBaseId,
    );
    if (index < 0) throw StateError('内置知识库不存在');
    final current = _bases[index];
    final restored = _builtInKnowledgeBase.copyWith(
      enabled: current.enabled,
      sortOrder: current.sortOrder,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _bases[index] = restored;
    return (
      result: null,
      persist: () => _repository.saveChanges(upsertBases: [restored]),
    );
  });

  Future<void> restoreBuiltInCategory() => _runMutation(() {
    final index = _categories.indexWhere(
      (item) => item.id == builtInProperNounCategoryId,
    );
    if (index < 0) throw StateError('内置类别不存在');
    final current = _categories[index];
    final renamed = _renameAliasConflicts(
      properNounAlias,
      excludingId: current.id,
    );
    final restored = _builtInProperNounCategory.copyWith(
      enabled: current.enabled,
      sortOrder: current.sortOrder,
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    _categories[index] = restored;
    _sortAll();
    return (
      result: null,
      persist: () =>
          _repository.saveChanges(upsertCategories: [...renamed, restored]),
    );
  });

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

  ({KnowledgeLoadResult value, bool changed}) _setData(
    KnowledgeLoadResult value,
  ) {
    final original = value;
    _bases = List.of(value.bases);
    if (!_bases.any((item) => item.id == builtInProperNounKnowledgeBaseId)) {
      _bases.add(_builtInKnowledgeBase);
    }
    final baseIds = _bases.map((item) => item.id).toSet();
    _categories = value.categories
        .where(
          (item) =>
              item.id == builtInProperNounCategoryId ||
              baseIds.contains(item.knowledgeBaseId),
        )
        .toList();
    final builtInIndex = _categories.indexWhere(
      (item) => item.id == builtInProperNounCategoryId,
    );
    if (builtInIndex < 0) {
      _renameAliasConflicts(properNounAlias);
      _categories.add(_builtInProperNounCategory);
    } else {
      final builtIn = _categories[builtInIndex];
      if (builtIn.knowledgeBaseId != builtInProperNounKnowledgeBaseId) {
        _categories[builtInIndex] = builtIn.copyWith(
          knowledgeBaseId: builtInProperNounKnowledgeBaseId,
        );
      }
      _renameAliasConflicts(
        _categories[builtInIndex].alias,
        excludingId: builtInProperNounCategoryId,
      );
    }
    _renameDuplicateAliases();
    final categoryById = {for (final item in _categories) item.id: item};
    _entries = value.entries
        .where((item) => baseIds.contains(item.knowledgeBaseId))
        .map((item) {
          final category = item.categoryId == null
              ? null
              : categoryById[item.categoryId];
          return item.categoryId == null ||
                  (category != null &&
                      category.knowledgeBaseId == item.knowledgeBaseId)
              ? item
              : item.copyWith(categoryId: null);
        })
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
    final normalized = KnowledgeLoadResult(
      bases: List.of(_bases),
      categories: List.of(_categories),
      entries: List.of(_entries),
      sources: List.of(_sources),
      explanations: List.of(_explanations),
    );
    return (value: normalized, changed: !_sameLoadResult(original, normalized));
  }

  List<KnowledgeCategory> _renameAliasConflicts(
    String alias, {
    String? excludingId,
  }) {
    return _normalizeCategoryAliases();
  }

  List<KnowledgeCategory> _renameDuplicateAliases() {
    return _normalizeCategoryAliases();
  }

  List<KnowledgeCategory> _normalizeCategoryAliases() {
    final aliases = normalizeKnowledgeCategoryAliases(
      _categories.map((item) => (id: item.id, alias: item.alias)),
    );
    final changed = <KnowledgeCategory>[];
    for (var index = 0; index < _categories.length; index++) {
      final category = _categories[index];
      final alias = aliases[category.id]!;
      if (alias == category.alias) continue;
      final renamed = category.copyWith(alias: alias);
      _categories[index] = renamed;
      changed.add(renamed);
    }
    return changed;
  }

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

bool _sameLoadResult(KnowledgeLoadResult a, KnowledgeLoadResult b) =>
    _sameJsonLists(a.bases, b.bases) &&
    _sameJsonLists(a.categories, b.categories) &&
    _sameJsonLists(a.entries, b.entries) &&
    _sameJsonLists(a.sources, b.sources) &&
    _sameJsonLists(a.explanations, b.explanations);

bool _sameJsonLists(List<dynamic> a, List<dynamic> b) {
  if (a.length != b.length) return false;
  for (var index = 0; index < a.length; index++) {
    if (!mapEquals(
      a[index].toJson() as Map<String, dynamic>,
      b[index].toJson() as Map<String, dynamic>,
    )) {
      return false;
    }
  }
  return true;
}

final class _KnowledgeMutationSnapshot {
  _KnowledgeMutationSnapshot({
    required this.bases,
    required this.categories,
    required this.entries,
    required this.sources,
    required this.explanations,
    required this.generation,
  });

  factory _KnowledgeMutationSnapshot.capture(KnowledgeProvider provider) =>
      _KnowledgeMutationSnapshot(
        bases: List.of(provider._bases),
        categories: List.of(provider._categories),
        entries: List.of(provider._entries),
        sources: List.of(provider._sources),
        explanations: List.of(provider._explanations),
        generation: provider._mutationGeneration,
      );

  final List<KnowledgeBase> bases;
  final List<KnowledgeCategory> categories;
  final List<KnowledgeEntry> entries;
  final List<KnowledgeSource> sources;
  final List<KnowledgeExplanation> explanations;
  final int generation;

  void restore(KnowledgeProvider provider) {
    provider._bases = List.of(bases);
    provider._categories = List.of(categories);
    provider._entries = List.of(entries);
    provider._sources = List.of(sources);
    provider._explanations = List.of(explanations);
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

final _builtInKnowledgeBase = KnowledgeBase(
  id: KnowledgeProvider.builtInProperNounKnowledgeBaseId,
  name: '专有名词知识库',
  description: '用于保存对话中识别和解释的专有名词。',
  enabled: true,
  sortOrder: 0,
  createdAt: KnowledgeProvider.builtInInitialTime,
  updatedAt: KnowledgeProvider.builtInInitialTime,
);

final _builtInProperNounCategory = KnowledgeCategory(
  id: KnowledgeProvider.builtInProperNounCategoryId,
  knowledgeBaseId: KnowledgeProvider.builtInProperNounKnowledgeBaseId,
  name: '专有名词',
  alias: KnowledgeProvider.properNounAlias,
  description: '人物、地点、组织、作品、产品及其他需要解释的专有名称。',
  annotationRule: KnowledgeProvider.defaultAnnotationRule,
  explanationPrompt: '结合上下文解释该专有名词，并给出简洁、准确的背景信息。',
  colorValue: 0xFF5B8DEF,
  autoAnnotate: true,
  enabled: true,
  sortOrder: 0,
  createdAt: KnowledgeProvider.builtInInitialTime,
  updatedAt: KnowledgeProvider.builtInInitialTime,
);
