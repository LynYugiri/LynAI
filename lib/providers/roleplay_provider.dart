import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/roleplay.dart';
import '../models/model_config.dart';
import '../repositories/roleplay_repository.dart';
import '../services/storage_v2_service.dart';

enum RoleplayRunState { idle, directing, speaking, waitingUser, error }

class RoleplayProvider extends ChangeNotifier {
  RoleplayProvider({
    StorageV2Service? storageV2,
    RoleplayRepository? repository,
  }) : _repository = repository ?? RoleplayRepository(storageV2: storageV2);

  final RoleplayRepository _repository;
  final _uuid = const Uuid();
  Future<void> _saveQueue = Future.value();
  List<RoleplaySession> _sessions = [];
  bool _usingStorageV2 = false;
  RoleplayRunState _runState = RoleplayRunState.idle;
  String? _activeSessionId;
  String? _activeSpeakerName;
  String? _draftContent;
  String? _errorMessage;
  final Map<String, List<String>> _pendingPlayerMessagesBySession = {};

  List<RoleplaySession> get sessions => List.unmodifiable(_sessions);
  bool get usingStorageV2 => _usingStorageV2;
  RoleplayRunState get runState => _runState;
  String? get activeSessionId => _activeSessionId;
  String? get activeSpeakerName => _activeSpeakerName;
  String? get draftContent => _draftContent;
  String? get errorMessage => _errorMessage;
  List<String> pendingPlayerMessages(String sessionId) => List.unmodifiable(
    _pendingPlayerMessagesBySession[sessionId] ?? const <String>[],
  );

  Future<void> loadSessions() async {
    try {
      final result = await _repository.load();
      _sessions = List<RoleplaySession>.from(result.sessions);
      _usingStorageV2 = result.usingStorageV2;
      notifyListeners();
    } catch (e) {
      debugPrint('加载情景演绎失败: $e');
      _sessions = [];
      notifyListeners();
    }
  }

  Future<void> replaceSessions(List<RoleplaySession> sessions) async {
    _sessions = List<RoleplaySession>.from(sessions)
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    _queueSave();
    await _saveQueue;
    notifyListeners();
  }

  void repairModelReferences(List<ModelConfig> models) {
    final chatIds = models
        .where((model) => model.category == ModelConfig.categoryChat)
        .map((model) => model.id)
        .toSet();
    var changed = false;
    _sessions = _sessions.map((session) {
      final directorModelId = session.director.modelId;
      final director =
          directorModelId != null && !chatIds.contains(directorModelId)
          ? RoleplayDirector(
              name: session.director.name,
              systemPrompt: session.director.systemPrompt,
            )
          : session.director;
      if (!identical(director, session.director)) changed = true;
      final participants = session.participants.map((participant) {
        final modelId = participant.modelId;
        if (modelId == null || chatIds.contains(modelId)) return participant;
        changed = true;
        return RoleplayParticipant(
          id: participant.id,
          sourceRoleId: participant.sourceRoleId,
          name: participant.name,
          description: participant.description,
          systemPrompt: participant.systemPrompt,
          themeColor: participant.themeColor,
          isPlayer: participant.isPlayer,
        );
      }).toList();
      return session.copyWith(director: director, participants: participants);
    }).toList();
    if (!changed) return;
    _queueSave();
    notifyListeners();
  }

  RoleplaySession? getSession(String id) {
    for (final session in _sessions) {
      if (session.id == id) return session;
    }
    return null;
  }

  String createSession({
    required String title,
    required String scenario,
    required RoleplayDirector director,
    required List<RoleplayParticipant> participants,
    required String playerParticipantId,
    int maxAutoTurns = 3,
  }) {
    final now = DateTime.now();
    final session = RoleplaySession(
      id: _uuid.v4(),
      title: title.trim().isEmpty ? _titleFromScenario(scenario) : title.trim(),
      scenario: scenario,
      director: director,
      participants: participants,
      playerParticipantId: playerParticipantId,
      maxAutoTurns: maxAutoTurns,
      createdAt: now,
      updatedAt: now,
    );
    _sessions.insert(0, session);
    _queueSave();
    notifyListeners();
    return session.id;
  }

  void deleteSession(String id) {
    final before = _sessions.length;
    _sessions.removeWhere((session) => session.id == id);
    if (_sessions.length == before) return;
    _pendingPlayerMessagesBySession.remove(id);
    if (_activeSessionId == id) {
      _runState = RoleplayRunState.idle;
      _activeSessionId = null;
      _activeSpeakerName = null;
      _draftContent = null;
      _errorMessage = null;
    }
    _queueSave();
    notifyListeners();
  }

  bool tryStartRun(String sessionId) {
    if (_activeSessionId != null &&
        _runState != RoleplayRunState.idle &&
        _runState != RoleplayRunState.waitingUser &&
        _runState != RoleplayRunState.error) {
      return false;
    }
    return true;
  }

  void queuePlayerMessage(String sessionId, String content) {
    final trimmed = content.trim();
    if (trimmed.isEmpty) return;
    (_pendingPlayerMessagesBySession[sessionId] ??= []).add(trimmed);
    notifyListeners();
  }

  List<String> drainPendingPlayerMessages(String sessionId) {
    final messages = List<String>.from(
      _pendingPlayerMessagesBySession[sessionId] ?? const <String>[],
    );
    _pendingPlayerMessagesBySession.remove(sessionId);
    return messages;
  }

  void appendPlayerMessage(String sessionId, String content) {
    final session = getSession(sessionId);
    final player = session?.player;
    if (session == null || player == null) return;
    _appendMessage(
      sessionId,
      RoleplayMessage(
        id: _uuid.v4(),
        speakerId: player.id,
        speakerName: player.name,
        content: content,
        kind: RoleplayMessageKind.player,
        timestamp: DateTime.now(),
      ),
    );
  }

  void appendCharacterMessage(
    String sessionId,
    RoleplayParticipant participant,
    String content,
  ) {
    _appendMessage(
      sessionId,
      RoleplayMessage(
        id: _uuid.v4(),
        speakerId: participant.id,
        speakerName: participant.name,
        content: content,
        kind: RoleplayMessageKind.character,
        timestamp: DateTime.now(),
      ),
    );
  }

  void appendNarratorMessage(String sessionId, String content) {
    _appendMessage(
      sessionId,
      RoleplayMessage(
        id: _uuid.v4(),
        speakerId: '__narrator__',
        speakerName: '系统',
        content: content,
        kind: RoleplayMessageKind.narrator,
        timestamp: DateTime.now(),
      ),
    );
  }

  void setRunState(
    RoleplayRunState state, {
    String? sessionId,
    String? speakerName,
    String? draftContent,
    String? errorMessage,
  }) {
    _runState = state;
    _activeSessionId = sessionId;
    _activeSpeakerName = speakerName;
    _draftContent = draftContent;
    _errorMessage = errorMessage;
    notifyListeners();
  }

  void updateDraft(String content) {
    if (_draftContent == content) return;
    _draftContent = content;
    notifyListeners();
  }

  void _appendMessage(String sessionId, RoleplayMessage message) {
    final index = _sessions.indexWhere((session) => session.id == sessionId);
    if (index == -1) return;
    final session = _sessions[index];
    _sessions[index] = session.copyWith(
      messages: [...session.messages, message],
      updatedAt: DateTime.now(),
    );
    final updated = _sessions.removeAt(index);
    _sessions.insert(0, updated);
    _queueSave();
    notifyListeners();
  }

  void _queueSave() {
    final snapshot = List<RoleplaySession>.from(_sessions);
    _saveQueue = _saveQueue.then(
      (_) => _repository.save(snapshot, usingStorageV2: _usingStorageV2),
    );
  }

  String _titleFromScenario(String scenario) {
    final clean = scenario.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (clean.isEmpty) return '情景演绎';
    return clean.length > 16 ? '${clean.substring(0, 16)}...' : clean;
  }
}
