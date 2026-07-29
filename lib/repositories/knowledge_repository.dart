import 'package:flutter/foundation.dart';

import '../models/knowledge_base.dart';
import '../models/knowledge_category.dart';
import '../models/knowledge_entry.dart';
import '../models/knowledge_explanation.dart';
import '../models/knowledge_source.dart';
import '../models/knowledge_settings.dart';
import '../services/storage_v2_service.dart';

final class KnowledgeLoadResult {
  const KnowledgeLoadResult({
    required this.bases,
    required this.categories,
    required this.entries,
    required this.sources,
    required this.explanations,
    this.settings,
  });

  final List<KnowledgeBase> bases;
  final List<KnowledgeCategory> categories;
  final List<KnowledgeEntry> entries;
  final List<KnowledgeSource> sources;
  final List<KnowledgeExplanation> explanations;
  final KnowledgeSettings? settings;
}

class KnowledgeRepository {
  KnowledgeRepository({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  static const fileName = 'knowledge.json';
  final StorageV2Service _storageV2;

  Future<KnowledgeLoadResult> load() async {
    final data = await _storageV2.loadDataFile(fileName);
    return KnowledgeLoadResult(
      bases: _decode(data['knowledgeBases'], KnowledgeBase.fromJson, '知识库'),
      categories: _decode(
        data['categories'],
        KnowledgeCategory.fromJson,
        '知识类别',
      ),
      entries: _decode(data['entries'], KnowledgeEntry.fromJson, '知识条目'),
      sources: _decode(data['sources'], KnowledgeSource.fromJson, '知识来源'),
      explanations: _decode(
        data['explanations'],
        KnowledgeExplanation.fromJson,
        '知识解释',
      ),
      settings: _decodeSettings(data['settings']),
    );
  }

  Future<void> replace(KnowledgeLoadResult value) =>
      _storageV2.writeDataFile(fileName, {
        'knowledgeBases': value.bases.map((item) => item.toJson()).toList(),
        'categories': value.categories.map((item) => item.toJson()).toList(),
        'entries': value.entries.map((item) => item.toJson()).toList(),
        'sources': value.sources.map((item) => item.toJson()).toList(),
        'explanations': value.explanations
            .map((item) => item.toJson())
            .toList(),
        if (value.settings != null) 'settings': value.settings!.toJson(),
      });

  Future<void> saveChanges({
    Iterable<KnowledgeBase> upsertBases = const [],
    Iterable<String> deleteBaseIds = const [],
    Iterable<KnowledgeCategory> upsertCategories = const [],
    Iterable<String> deleteCategoryIds = const [],
    Iterable<KnowledgeEntry> upsertEntries = const [],
    Iterable<String> deleteEntryIds = const [],
    Iterable<KnowledgeSource> upsertSources = const [],
    Iterable<String> deleteSourceIds = const [],
    Iterable<KnowledgeExplanation> upsertExplanations = const [],
    Iterable<String> deleteExplanationIds = const [],
    KnowledgeSettings? settings,
  }) async {
    final operations = [
      for (final id in deleteSourceIds)
        (
          table: 'knowledge_sources',
          op: 'delete',
          data: {'id': id},
          change: null,
        ),
      for (final id in deleteExplanationIds)
        (
          table: 'knowledge_explanations',
          op: 'delete',
          data: {'id': id},
          change: null,
        ),
      for (final id in deleteEntryIds)
        (
          table: 'knowledge_entries',
          op: 'delete',
          data: {'id': id},
          change: null,
        ),
      for (final id in deleteCategoryIds)
        (
          table: 'knowledge_categories',
          op: 'delete',
          data: {'id': id},
          change: null,
        ),
      for (final id in deleteBaseIds)
        (
          table: 'knowledge_bases',
          op: 'delete',
          data: {'id': id},
          change: null,
        ),
      for (final item in upsertBases)
        (
          table: 'knowledge_bases',
          op: 'upsert',
          data: item.toJson(),
          change: null,
        ),
      for (final item in upsertCategories)
        (
          table: 'knowledge_categories',
          op: 'upsert',
          data: item.toJson(),
          change: null,
        ),
      if (settings != null)
        (
          table: 'knowledge_settings',
          op: 'upsert',
          data: {'id': 'global', ...settings.toJson()},
          change: null,
        ),
      for (final item in upsertEntries)
        (
          table: 'knowledge_entries',
          op: 'upsert',
          data: item.toJson(),
          change: null,
        ),
      for (final item in upsertSources)
        (
          table: 'knowledge_sources',
          op: 'upsert',
          data: item.toJson(),
          change: null,
        ),
      for (final item in upsertExplanations)
        (
          table: 'knowledge_explanations',
          op: 'upsert',
          data: item.toJson(),
          change: null,
        ),
    ];
    await _storageV2.applyLocalRowChanges(operations);
  }
}

KnowledgeSettings? _decodeSettings(Object? raw) {
  if (raw is! Map) return null;
  try {
    return KnowledgeSettings.fromJson(Map<String, dynamic>.from(raw));
  } catch (error) {
    debugPrint('跳过损坏的知识库设置: $error');
    return null;
  }
}

List<T> _decode<T>(
  Object? raw,
  T Function(Map<String, dynamic>) parser,
  String label,
) {
  final values = <T>[];
  for (final item in raw as List<dynamic>? ?? const []) {
    try {
      if (item is Map) values.add(parser(Map<String, dynamic>.from(item)));
    } catch (error) {
      debugPrint('跳过损坏的$label: $error');
    }
  }
  return values;
}
