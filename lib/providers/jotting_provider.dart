import 'package:flutter/foundation.dart';
import 'package:uuid/uuid.dart';

import '../models/jotting.dart';
import '../models/local_date.dart';
import '../models/recycle_bin_item.dart';
import '../repositories/jotting_repository.dart';
import '../repositories/recycle_bin_repository.dart';
import '../services/storage_v2_service.dart';
import 'serialized_save_queue.dart';

/// 随记查询过滤器。
///
/// 所有条件为 AND 关系；`query` 为字面大小写不敏感匹配，正则语法由页面
/// 自行使用 [FeatureSearchMatcher] 处理。
class JottingSearchFilter {
  const JottingSearchFilter({
    this.query = '',
    this.tags = const [],
    this.dateFrom,
    this.dateTo,
    this.limit,
  });

  final String query;
  final List<String> tags;
  final LocalDate? dateFrom;
  final LocalDate? dateTo;
  final int? limit;

  bool get isEmpty =>
      query.trim().isEmpty &&
      tags.isEmpty &&
      dateFrom == null &&
      dateTo == null;
}

/// 管理随记的内存状态与串行持久化。
class JottingProvider extends ChangeNotifier with SerializedSaveQueue {
  JottingProvider({
    StorageV2Service? storageV2,
    JottingRepository? repository,
    RecycleBinRepository? recycleBinRepository,
  }) : _repository = repository ?? JottingRepository(storageV2: storageV2),
       _recycleBinRepository =
           recycleBinRepository ?? RecycleBinRepository(storageV2: storageV2);

  final JottingRepository _repository;
  final RecycleBinRepository _recycleBinRepository;
  final _uuid = const Uuid();
  List<Jotting> _jottings = [];
  int _mutationGeneration = 0;

  /// 按 `createdAt DESC, id` 排序的只读列表。
  List<Jotting> get jottings => List.unmodifiable(_jottings);

  Jotting? byId(String id) {
    for (final item in _jottings) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// 现有标签按出现次数降序、名称升序返回。
  List<String> tagCounts() {
    final counts = <String, int>{};
    for (final item in _jottings) {
      for (final tag in item.tags) {
        counts[tag] = (counts[tag] ?? 0) + 1;
      }
    }
    final tags = counts.keys.toList()
      ..sort((a, b) {
        final countCompare = counts[b]!.compareTo(counts[a]!);
        return countCompare != 0 ? countCompare : a.compareTo(b);
      });
    return tags;
  }

  Future<void> load() async {
    final generation = _mutationGeneration;
    await flushPendingSaves();
    final result = await _repository.load();
    if (generation != _mutationGeneration) return;
    _jottings = _normalize(result.jottings);
    notifyListeners();
  }

  Future<String> add(
    String content, {
    List<String> tags = const [],
    DateTime? createdAt,
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(content, 'content', '随记内容不能为空');
    }
    final now = createdAt ?? DateTime.now();
    final item = Jotting(
      id: _uuid.v4(),
      content: trimmed,
      tags: Jotting.normalizeTags(tags),
      createdAt: now,
      updatedAt: now,
    );
    _mutationGeneration++;
    _jottings = _normalize([..._jottings, item]);
    notifyListeners();
    try {
      await enqueueSave(() => _repository.replace(_snapshot()));
    } catch (_) {
      final index = _jottings.indexWhere((value) => value.id == item.id);
      if (index >= 0 && _sameJotting(_jottings[index], item)) {
        _mutationGeneration++;
        _jottings = List.of(_jottings)..removeAt(index);
        notifyListeners();
      }
      rethrow;
    }
    return item.id;
  }

  Future<void> update(
    String id, {
    required String content,
    List<String> tags = const [],
  }) async {
    final trimmed = content.trim();
    if (trimmed.isEmpty) {
      throw ArgumentError.value(content, 'content', '随记内容不能为空');
    }
    final index = _jottings.indexWhere((item) => item.id == id);
    if (index < 0) return;
    final before = List<Jotting>.from(_jottings);
    final current = _jottings[index];
    _mutationGeneration++;
    final updated = Jotting(
      id: current.id,
      content: trimmed,
      tags: Jotting.normalizeTags(tags),
      createdAt: current.createdAt,
      updatedAt: DateTime.now(),
    );
    final next = [..._jottings];
    next[index] = updated;
    _jottings = _normalize(next);
    notifyListeners();
    try {
      await enqueueSave(() => _repository.replace(_snapshot()));
    } catch (_) {
      _mutationGeneration++;
      _jottings = before;
      notifyListeners();
      rethrow;
    }
  }

  Future<void> delete(String id) async {
    final item = byId(id);
    if (item == null) return;
    _mutationGeneration++;
    await _recycleBinRepository.add(
      RecycleBinItem(
        owner: RecycleBinOwners.core,
        category: RecycleBinCategories.jottings,
        type: RecycleBinItemTypes.jotting,
        title: _displayTitle(item),
        preview: item.content.replaceAll(RegExp(r'\s+'), ' ').trim(),
        payload: {'jotting': item.toJson()},
      ),
    );
    final before = _jottings.length;
    _jottings = List.of(_jottings)..removeWhere((value) => value.id == id);
    if (_jottings.length == before) return;
    notifyListeners();
    await enqueueSave(() => _repository.replace(_snapshot()));
  }

  Future<void> restorePayload(Map<String, dynamic> payload) async {
    final raw = payload['jotting'];
    if (raw is! Map) return;
    final item = Jotting.fromJson(Map<String, dynamic>.from(raw));
    if (byId(item.id) != null) return;
    _mutationGeneration++;
    _jottings = _normalize([..._jottings, item]);
    notifyListeners();
    await enqueueSave(() => _repository.replace(_snapshot()));
  }

  /// 按过滤器返回命中的随记，保持时间倒序。
  List<Jotting> search(JottingSearchFilter filter) {
    final query = filter.query.trim().toLowerCase();
    final tags = Jotting.normalizeTags(filter.tags);
    final from = filter.dateFrom?.atStartOfDay();
    final toExclusive = filter.dateTo?.addDays(1).atStartOfDay();
    final result = <Jotting>[];
    for (final item in _jottings) {
      if (query.isNotEmpty &&
          !item.content.toLowerCase().contains(query) &&
          !item.tags.any((tag) => tag.contains(query))) {
        continue;
      }
      if (tags.isNotEmpty && !tags.every(item.tags.contains)) continue;
      final localCreatedAt = item.createdAt.toLocal();
      if (from != null && localCreatedAt.isBefore(from)) continue;
      if (toExclusive != null && !localCreatedAt.isBefore(toExclusive)) {
        continue;
      }
      result.add(item);
      if (filter.limit != null && result.length >= filter.limit!) break;
    }
    return List.unmodifiable(result);
  }

  /// 返回过去年份中与 [today] 同月同日的随记，按时间倒序。
  List<Jotting> onThisDay(LocalDate today) {
    final result = <Jotting>[];
    for (final item in _jottings) {
      final local = item.createdAt.toLocal();
      final createdAtDate = LocalDate.fromDateTime(local);
      if (createdAtDate.year >= today.year) continue;
      if (createdAtDate.month == today.month &&
          createdAtDate.day == today.day) {
        result.add(item);
      }
    }
    return List.unmodifiable(result);
  }

  String _displayTitle(Jotting item) {
    final firstLine = item.content
        .split('\n')
        .map((line) => line.trim())
        .firstWhere((line) => line.isNotEmpty, orElse: () => '');
    if (firstLine.isEmpty) return '未命名随记';
    if (firstLine.length <= 24) return firstLine;
    return '${firstLine.substring(0, 24)}…';
  }

  List<Jotting> _normalize(Iterable<Jotting> values) {
    final seen = <String>{};
    final result = <Jotting>[];
    for (final item in values) {
      if (!seen.add(item.id)) continue;
      result.add(
        Jotting(
          id: item.id,
          content: item.content,
          tags: Jotting.normalizeTags(item.tags),
          createdAt: item.createdAt,
          updatedAt: item.updatedAt,
        ),
      );
    }
    result.sort((a, b) {
      final createdCompare = b.createdAt.compareTo(a.createdAt);
      return createdCompare != 0 ? createdCompare : a.id.compareTo(b.id);
    });
    return result;
  }

  bool _sameJotting(Jotting left, Jotting right) {
    return left.id == right.id &&
        left.content == right.content &&
        listEquals(left.tags, right.tags) &&
        left.createdAt == right.createdAt &&
        left.updatedAt == right.updatedAt;
  }

  JottingLoadResult _snapshot() {
    return JottingLoadResult(jottings: List.unmodifiable(_jottings));
  }
}
