import 'package:flutter/material.dart';

import '../models/recycle_bin_item.dart';
import '../repositories/recycle_bin_repository.dart';
import '../services/storage_v2_service.dart';

class RecycleBinProvider extends ChangeNotifier {
  RecycleBinProvider({
    StorageV2Service? storageV2,
    RecycleBinRepository? repository,
  }) : _repository = repository ?? RecycleBinRepository(storageV2: storageV2);

  final RecycleBinRepository _repository;
  List<RecycleBinItem> _items = const [];
  bool _loading = false;

  List<RecycleBinItem> get items => List.unmodifiable(_items);
  bool get loading => _loading;

  int countForCategory(String category) {
    return _items.where((item) => item.category == category).length;
  }

  List<RecycleBinCategorySummary> get categories {
    final counts = <String, int>{};
    for (final item in _items) {
      counts[item.category] = (counts[item.category] ?? 0) + 1;
    }
    final result = <RecycleBinCategorySummary>[];
    for (final entry in counts.entries) {
      result.add(
        RecycleBinCategorySummary(
          id: entry.key,
          title: categoryTitle(entry.key),
          group: entry.key.startsWith('plugin:') ? 'plugin' : 'core',
          count: entry.value,
        ),
      );
    }
    result.sort((a, b) => a.title.compareTo(b.title));
    return result;
  }

  Future<void> load() async {
    _loading = true;
    notifyListeners();
    try {
      _items = await _repository.load();
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> addItem(RecycleBinItem item) async {
    await _repository.add(item);
    await load();
  }

  Future<void> deleteForever(String id) async {
    await _repository.remove(id);
    _items = _items.where((item) => item.id != id).toList();
    notifyListeners();
  }

  Future<void> clear() async {
    await _repository.save(const []);
    _items = const [];
    notifyListeners();
  }

  String categoryTitle(String category) {
    return switch (category) {
      RecycleBinCategories.conversations => '对话',
      RecycleBinCategories.notes => '笔记',
      RecycleBinCategories.schedules => '日程',
      RecycleBinCategories.todos => '待办',
      RecycleBinCategories.roleplay => '角色扮演',
      String value when value.startsWith('plugin:') => _pluginCategoryTitle(
        value,
      ),
      _ => category,
    };
  }

  String _pluginCategoryTitle(String category) {
    final parts = category.split(':');
    if (parts.length < 3) return '插件';
    final name = parts.sublist(2).join(':');
    if (name == 'files') return '插件文件';
    return '插件 · $name';
  }
}
