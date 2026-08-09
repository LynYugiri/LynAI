import 'package:flutter/foundation.dart';

import '../models/knowledge_base.dart';
import '../models/knowledge_category.dart';
import '../models/knowledge_entry.dart';
import '../models/knowledge_explanation.dart';
import '../models/knowledge_source.dart';
import '../services/storage_v2_service.dart';

/// 从持久化层一次性读取的知识数据快照。
final class KnowledgeLoadResult {
  const KnowledgeLoadResult({
    required this.bases,
    required this.categories,
    required this.entries,
    required this.sources,
    required this.explanations,
  });

  final List<KnowledgeBase> bases;
  final List<KnowledgeCategory> categories;
  final List<KnowledgeEntry> entries;
  final List<KnowledgeSource> sources;
  final List<KnowledgeExplanation> explanations;
}

/// 负责知识数据与 storage_v2 行存储之间的转换。
class KnowledgeRepository {
  KnowledgeRepository({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  static const fileName = 'knowledge.json';
  final StorageV2Service _storageV2;

  /// 读取知识数据。
  ///
  /// 缺失或为 null 的顶层集合按空列表处理；存在但不是列表时抛出
  /// [FormatException]。列表内类型错误或无法解析的记录会被跳过。
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
    );
  }

  /// 使用完整快照替换当前知识数据。
  Future<void> replace(KnowledgeLoadResult value) =>
      _storageV2.writeDataFile(fileName, {
        'knowledgeBases': value.bases.map((item) => item.toJson()).toList(),
        'categories': value.categories.map((item) => item.toJson()).toList(),
        'entries': value.entries.map((item) => item.toJson()).toList(),
        'sources': value.sources.map((item) => item.toJson()).toList(),
        'explanations': value.explanations
            .map((item) => item.toJson())
            .toList(),
      });

  /// 原子应用知识行的增量新增、更新与删除。
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

List<T> _decode<T>(
  Object? raw,
  T Function(Map<String, dynamic>) parser,
  String label,
) {
  if (raw == null) return const [];
  if (raw is! List) {
    throw FormatException('$label集合必须是列表');
  }
  final values = <T>[];
  for (final item in raw) {
    try {
      if (item is Map) values.add(parser(Map<String, dynamic>.from(item)));
    } catch (error) {
      debugPrint('跳过损坏的$label: $error');
    }
  }
  return values;
}
