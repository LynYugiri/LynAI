import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/roleplay.dart';
import '../services/storage_v2_service.dart';
import 'app_storage_state.dart';

class RoleplayLoadResult {
  final List<RoleplayScenario> scenarios;
  final List<RoleplayThread> threads;
  final bool usingStorageV2;

  const RoleplayLoadResult({
    required this.scenarios,
    required this.threads,
    required this.usingStorageV2,
  });
}

class RoleplayRepository {
  factory RoleplayRepository({
    StorageV2Service? storageV2,
    AppStorageStateRepository? storageState,
  }) {
    final storage = storageV2 ?? StorageV2Service();
    return RoleplayRepository._(
      storage,
      storageState ?? AppStorageStateRepository(storageV2: storage),
    );
  }

  RoleplayRepository._(this._storageV2, this._storageState);

  static const _scenariosFile = 'roleplay_scenarios.json';
  static const _threadsFile = 'roleplay_threads.json';
  static const _legacyScenariosKey = 'roleplay_scenarios_v2';
  static const _legacyThreadsKey = 'roleplay_threads_v2';

  final StorageV2Service _storageV2;
  final AppStorageStateRepository _storageState;

  Future<RoleplayLoadResult> load() async {
    final usingV2 = await _storageState.isStorageV2Active();
    if (!usingV2) {
      final legacy = await _loadSharedPreferences();
      return RoleplayLoadResult(
        scenarios: legacy.scenarios,
        threads: legacy.threads,
        usingStorageV2: false,
      );
    }
    try {
      final scenarioData = await _loadStorageV2File(_scenariosFile);
      final threadData = await _loadStorageV2File(_threadsFile);
      final scenarios = _parseScenarios(scenarioData['scenarios']);
      final threads = _parseThreads(threadData['threads']);
      if (scenarios.isEmpty && threads.isEmpty) {
        final fallback = await _loadSharedPreferences();
        if (fallback.scenarios.isNotEmpty || fallback.threads.isNotEmpty) {
          return RoleplayLoadResult(
            scenarios: fallback.scenarios,
            threads: fallback.threads,
            usingStorageV2: true,
          );
        }
      }
      return RoleplayLoadResult(
        scenarios: scenarios,
        threads: threads,
        usingStorageV2: usingV2,
      );
    } catch (e) {
      debugPrint('加载情景演绎失败: $e');
      return RoleplayLoadResult(
        scenarios: const [],
        threads: const [],
        usingStorageV2: usingV2,
      );
    }
  }

  Future<void> save({
    required List<RoleplayScenario> scenarios,
    required List<RoleplayThread> threads,
    required bool usingStorageV2,
  }) async {
    final scenarioData = {
      'scenarios': scenarios.map((item) => item.toJson()).toList(),
    };
    final threadData = {
      'threads': threads.map((item) => item.toJson()).toList(),
    };
    if (usingStorageV2 || await _isStorageV2Active()) {
      await _storageV2.writeDataFile(_scenariosFile, scenarioData);
      await _storageV2.writeDataFile(_threadsFile, threadData);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_legacyScenariosKey, jsonEncode(scenarioData));
    await prefs.setString(_legacyThreadsKey, jsonEncode(threadData));
  }

  Future<({List<RoleplayScenario> scenarios, List<RoleplayThread> threads})>
  _loadSharedPreferences() async {
    final prefs = await SharedPreferences.getInstance();
    return (
      scenarios: _parseScenarios(
        _decodePrefsMap(prefs.getString(_legacyScenariosKey))['scenarios'],
      ),
      threads: _parseThreads(
        _decodePrefsMap(prefs.getString(_legacyThreadsKey))['threads'],
      ),
    );
  }

  Map<String, dynamic> _decodePrefsMap(String? raw) {
    if (raw == null || raw.isEmpty) return const {};
    try {
      final data = jsonDecode(raw);
      return data is Map ? Map<String, dynamic>.from(data) : const {};
    } catch (e) {
      debugPrint('加载情景演绎 SharedPreferences 数据失败: $e');
      return const {};
    }
  }

  Future<Map<String, dynamic>> _loadStorageV2File(String fileName) async {
    try {
      return await _storageV2.loadDataFile(fileName);
    } catch (_) {
      return const {};
    }
  }

  Future<bool> _isStorageV2Active() async {
    try {
      return await _storageState.isStorageV2Active();
    } catch (_) {
      return false;
    }
  }

  List<RoleplayScenario> _parseScenarios(Object? raw) {
    final scenarios = <RoleplayScenario>[];
    for (final item in raw as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          scenarios.add(
            RoleplayScenario.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      } catch (e) {
        debugPrint('跳过损坏的情景: $e');
      }
    }
    scenarios.sort(_scenarioSort);
    return scenarios;
  }

  List<RoleplayThread> _parseThreads(Object? raw) {
    final threads = <RoleplayThread>[];
    for (final item in raw as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          threads.add(RoleplayThread.fromJson(Map<String, dynamic>.from(item)));
        }
      } catch (e) {
        debugPrint('跳过损坏的演绎对话: $e');
      }
    }
    threads.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return threads;
  }
}

int _scenarioSort(RoleplayScenario a, RoleplayScenario b) {
  if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
  return b.updatedAt.compareTo(a.updatedAt);
}
