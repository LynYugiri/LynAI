import 'package:flutter/foundation.dart';

import '../models/roleplay.dart';
import '../services/storage_v2_service.dart';

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
  factory RoleplayRepository({StorageV2Service? storageV2}) {
    final storage = storageV2 ?? StorageV2Service();
    return RoleplayRepository._(storage);
  }

  RoleplayRepository._(this._storageV2);

  static const _scenariosFile = 'roleplay_scenarios.json';
  static const _threadsFile = 'roleplay_threads.json';

  final StorageV2Service _storageV2;

  Future<RoleplayLoadResult> load() async {
    try {
      final scenarioData = await _loadStorageV2File(_scenariosFile);
      final threadData = await _loadStorageV2File(_threadsFile);
      final scenarios = _parseScenarios(scenarioData['scenarios']);
      final threads = _parseThreads(threadData['threads']);
      return RoleplayLoadResult(
        scenarios: scenarios,
        threads: threads,
        usingStorageV2: true,
      );
    } catch (e) {
      debugPrint('加载情景演绎失败: $e');
      return RoleplayLoadResult(
        scenarios: const [],
        threads: const [],
        usingStorageV2: true,
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
    await _storageV2.writeDataFile(_scenariosFile, scenarioData);
    await _storageV2.writeDataFile(_threadsFile, threadData);
  }

  Future<Map<String, dynamic>> _loadStorageV2File(String fileName) async {
    try {
      return await _storageV2.loadDataFile(fileName);
    } catch (_) {
      return const {};
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
