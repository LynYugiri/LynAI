import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/recycle_bin_item.dart';
import '../services/storage_v2_service.dart';
import 'app_storage_state.dart';

class RecycleBinRepository {
  factory RecycleBinRepository({
    StorageV2Service? storageV2,
    AppStorageStateRepository? storageState,
  }) {
    final storage = storageV2 ?? StorageV2Service();
    return RecycleBinRepository._(
      storage,
      storageState ?? AppStorageStateRepository(storageV2: storage),
    );
  }

  RecycleBinRepository._(this._storageV2, this._storageState);

  static const _storageKey = 'recycle_bin_items';
  static const _fileName = 'recycle_bin.json';
  static Future<void> _mutationQueue = Future.value();

  final StorageV2Service _storageV2;
  final AppStorageStateRepository _storageState;

  Future<List<RecycleBinItem>> load() async {
    final usingStorageV2 = await _isStorageV2Active();
    final rawItems = usingStorageV2
        ? (await _storageV2.loadDataFile(_fileName))['items']
        : jsonDecode(
            (await SharedPreferences.getInstance()).getString(_storageKey) ??
                '{"items":[]}',
          )['items'];
    final items = <RecycleBinItem>[];
    for (final item in rawItems as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          items.add(RecycleBinItem.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (e) {
        debugPrint('跳过损坏的回收站项目: $e');
      }
    }
    items.sort((a, b) => b.deletedAt.compareTo(a.deletedAt));
    return items;
  }

  Future<void> save(List<RecycleBinItem> items) async {
    await _withMutation(() => _writeItems(items));
  }

  Future<void> add(RecycleBinItem item) async {
    await _withMutation(() async {
      final items = await load();
      items.removeWhere((existing) => existing.id == item.id);
      items.insert(0, item);
      await _writeItems(items);
    });
  }

  Future<void> remove(String id) async {
    await _withMutation(() async {
      final items = await load();
      items.removeWhere((item) => item.id == id);
      await _writeItems(items);
    });
  }

  Future<void> _withMutation(Future<void> Function() action) {
    final run = _mutationQueue.catchError((_) {}).then((_) => action());
    _mutationQueue = run;
    return run;
  }

  Future<void> _writeItems(List<RecycleBinItem> items) async {
    final data = {'items': items.map((item) => item.toJson()).toList()};
    if (await _isStorageV2Active()) {
      await _storageV2.writeDataFile(_fileName, data);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_storageKey, const JsonEncoder().convert(data));
  }

  Future<bool> _isStorageV2Active() async {
    try {
      return await _storageState.isStorageV2Active();
    } catch (_) {
      return false;
    }
  }
}
