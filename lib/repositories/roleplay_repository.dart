import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/roleplay.dart';
import '../services/storage_v2_service.dart';
import 'app_storage_state.dart';

class RoleplayLoadResult {
  final List<RoleplaySession> sessions;
  final bool usingStorageV2;

  const RoleplayLoadResult({
    required this.sessions,
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

  static const _legacyKey = 'roleplay_sessions';
  static const _storageFile = 'roleplay_sessions.json';

  final StorageV2Service _storageV2;
  final AppStorageStateRepository _storageState;

  Future<RoleplayLoadResult> load() async {
    final legacy = await _loadLegacy();
    if (!await _storageState.isStorageV2Active()) {
      return RoleplayLoadResult(sessions: legacy, usingStorageV2: false);
    }
    try {
      final data = await _storageV2.loadDataFile(_storageFile);
      final sessions = _parseSessions(data['sessions']);
      return RoleplayLoadResult(sessions: sessions, usingStorageV2: true);
    } catch (e) {
      debugPrint('加载情景演绎新版存储失败，保留旧数据: $e');
      return RoleplayLoadResult(sessions: legacy, usingStorageV2: true);
    }
  }

  Future<void> save(
    List<RoleplaySession> sessions, {
    required bool usingStorageV2,
  }) async {
    final data = {'sessions': sessions.map((item) => item.toJson()).toList()};
    if (usingStorageV2 || await _storageState.isStorageV2Active()) {
      await _storageV2.writeDataFile(_storageFile, data);
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_legacyKey, jsonEncode(data));
  }

  Future<List<RoleplaySession>> _loadLegacy() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_legacyKey);
    if (raw == null || raw.isEmpty) return const [];
    try {
      final data = jsonDecode(raw) as Map<String, dynamic>;
      return _parseSessions(data['sessions']);
    } catch (e) {
      debugPrint('加载情景演绎旧版存储失败: $e');
      return const [];
    }
  }

  List<RoleplaySession> _parseSessions(Object? raw) {
    final sessions = <RoleplaySession>[];
    for (final item in raw as List<dynamic>? ?? const []) {
      try {
        if (item is Map) {
          sessions.add(
            RoleplaySession.fromJson(Map<String, dynamic>.from(item)),
          );
        }
      } catch (e) {
        debugPrint('跳过损坏的情景演绎记录: $e');
      }
    }
    sessions.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return sessions;
  }
}
