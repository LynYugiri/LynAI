import 'package:flutter/material.dart';
import 'package:uuid/uuid.dart';

import '../models/chat_role.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../models/roleplay.dart';
import '../repositories/roleplay_repository.dart';
import '../services/storage_v2_service.dart';

enum RoleplayRunState { idle, directing, speaking, waitingUser, error }

class RoleplaySearchResult {
  final RoleplayScenario scenario;
  final RoleplayThread? thread;
  final bool matchInTitle;
  final String matchContent;

  const RoleplaySearchResult({
    required this.scenario,
    this.thread,
    this.matchInTitle = false,
    this.matchContent = '',
  });
}

class RoleplayProvider extends ChangeNotifier {
  RoleplayProvider({
    StorageV2Service? storageV2,
    RoleplayRepository? repository,
  }) : _repository = repository ?? RoleplayRepository(storageV2: storageV2);

  final RoleplayRepository _repository;
  final _uuid = const Uuid();
  Future<void> _saveQueue = Future.value();
  List<RoleplayScenario> _scenarios = [];
  List<RoleplayThread> _threads = [];
  bool _usingStorageV2 = false;
  RoleplayRunState _runState = RoleplayRunState.idle;
  String? _activeThreadId;
  String? _activeSpeakerName;
  String? _draftContent;
  String? _errorMessage;
  final Map<String, List<RoleplayQueuedPlayerMessage>>
  _pendingPlayerMessagesByThread = {};

  List<RoleplayScenario> get scenarios => List.unmodifiable(_sortedScenarios());
  List<RoleplayThread> get threads =>
      List.unmodifiable(_sortedThreads(_threads));
  bool get usingStorageV2 => _usingStorageV2;
  RoleplayRunState get runState => _runState;
  String? get activeThreadId => _activeThreadId;
  String? get activeSpeakerName => _activeSpeakerName;
  String? get draftContent => _draftContent;
  String? get errorMessage => _errorMessage;

  List<RoleplayQueuedPlayerMessage> pendingPlayerMessages(String threadId) =>
      List.unmodifiable(
        _pendingPlayerMessagesByThread[threadId] ??
            const <RoleplayQueuedPlayerMessage>[],
      );

  Future<void> loadSessions() async {
    try {
      final result = await _repository.load();
      _scenarios = List<RoleplayScenario>.from(result.scenarios);
      _threads = List<RoleplayThread>.from(result.threads);
      _usingStorageV2 = result.usingStorageV2;
      notifyListeners();
    } catch (e) {
      debugPrint('加载情景演绎失败: $e');
      _scenarios = [];
      _threads = [];
      notifyListeners();
    }
  }

  Future<void> replaceData({
    List<RoleplayScenario>? scenarios,
    List<RoleplayThread>? threads,
  }) async {
    _scenarios = List<RoleplayScenario>.from(scenarios ?? _scenarios);
    _threads = List<RoleplayThread>.from(threads ?? _threads);
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
    RoleplayModelSelection repair(RoleplayModelSelection selection) {
      final modelId = selection.modelId;
      if (modelId == null || modelId.isEmpty || chatIds.contains(modelId)) {
        return selection;
      }
      changed = true;
      return const RoleplayModelSelection();
    }

    RoleplayDirector repairDirector(RoleplayDirector director) {
      final next = repair(director.model);
      return identical(next, director.model)
          ? director
          : director.copyWith(model: next);
    }

    RoleplayParticipant repairParticipant(RoleplayParticipant participant) {
      final next = repair(participant.model);
      return identical(next, participant.model)
          ? participant
          : participant.copyWith(model: next);
    }

    _scenarios = _scenarios.map((scenario) {
      return scenario.copyWith(
        director: repairDirector(scenario.director),
        defaultPlayer: repairParticipant(scenario.defaultPlayer),
        defaultParticipants: scenario.defaultParticipants
            .map(repairParticipant)
            .toList(),
      );
    }).toList();
    _threads = _threads.map((thread) {
      return thread.copyWith(
        director: repairDirector(thread.director),
        participants: thread.participants.map(repairParticipant).toList(),
      );
    }).toList();
    if (!changed) return;
    _queueSave();
    notifyListeners();
  }

  RoleplayScenario? getScenario(String id) {
    for (final scenario in _scenarios) {
      if (scenario.id == id) return scenario;
    }
    return null;
  }

  RoleplayThread? getThread(String id) {
    for (final thread in _threads) {
      if (thread.id == id) return thread;
    }
    return null;
  }

  List<RoleplayThread> threadsForScenario(String scenarioId) {
    return _sortedThreads(
      _threads.where((thread) => thread.scenarioId == scenarioId).toList(),
    );
  }

  int nextThreadIndex(String scenarioId) {
    return _threads.where((thread) => thread.scenarioId == scenarioId).length +
        1;
  }

  String createScenario({
    required String title,
    String description = '',
    required String scenario,
    required RoleplayDirector director,
    required RoleplayParticipant defaultPlayer,
    required List<RoleplayParticipant> defaultParticipants,
    List<RoleplayParticipantGroup> defaultGroups = const [],
    int maxAutoTurns = 3,
  }) {
    final now = DateTime.now();
    final id = _uuid.v4();
    final item = RoleplayScenario(
      id: id,
      title: title.trim().isEmpty ? _titleFromScenario(scenario) : title.trim(),
      description: description.trim(),
      scenario: scenario.trim(),
      director: director,
      defaultPlayer: defaultPlayer.copyWith(isPlayer: true),
      defaultParticipants: defaultParticipants
          .map((item) => item.copyWith(isPlayer: false))
          .toList(),
      defaultGroups: defaultGroups,
      maxAutoTurns: maxAutoTurns < 0 ? 0 : maxAutoTurns,
      createdAt: now,
      updatedAt: now,
    );
    _scenarios.add(item);
    _queueSave();
    notifyListeners();
    return id;
  }

  void updateScenario(
    String id, {
    required String title,
    String description = '',
    required String scenario,
    required RoleplayDirector director,
    required RoleplayParticipant defaultPlayer,
    required List<RoleplayParticipant> defaultParticipants,
    required List<RoleplayParticipantGroup> defaultGroups,
    required int maxAutoTurns,
  }) {
    final index = _scenarios.indexWhere((item) => item.id == id);
    if (index == -1) return;
    _scenarios[index] = _scenarios[index].copyWith(
      title: title.trim().isEmpty ? _titleFromScenario(scenario) : title.trim(),
      description: description.trim(),
      scenario: scenario.trim(),
      director: director,
      defaultPlayer: defaultPlayer.copyWith(isPlayer: true),
      defaultParticipants: defaultParticipants
          .map((item) => item.copyWith(isPlayer: false))
          .toList(),
      defaultGroups: defaultGroups,
      maxAutoTurns: maxAutoTurns < 0 ? 0 : maxAutoTurns,
      updatedAt: DateTime.now(),
    );
    _queueSave();
    notifyListeners();
  }

  void toggleScenarioPinned(String id) {
    final index = _scenarios.indexWhere((item) => item.id == id);
    if (index == -1) return;
    final scenario = _scenarios[index];
    _scenarios[index] = scenario.copyWith(
      pinned: !scenario.pinned,
      updatedAt: DateTime.now(),
    );
    _queueSave();
    notifyListeners();
  }

  void deleteScenario(String id) {
    final before = _scenarios.length;
    _scenarios.removeWhere((scenario) => scenario.id == id);
    if (_scenarios.length == before) return;
    final deletedThreadIds = _threads
        .where((thread) => thread.scenarioId == id)
        .map((thread) => thread.id)
        .toSet();
    _threads.removeWhere((thread) => thread.scenarioId == id);
    for (final threadId in deletedThreadIds) {
      _pendingPlayerMessagesByThread.remove(threadId);
    }
    if (_activeThreadId != null && deletedThreadIds.contains(_activeThreadId)) {
      setRunState(RoleplayRunState.idle);
    }
    _queueSave();
    notifyListeners();
  }

  String createThread(String scenarioId) {
    final scenario = getScenario(scenarioId);
    if (scenario == null) return '';
    final now = DateTime.now();
    final threadId = _uuid.v4();
    final player = _copyParticipant(scenario.defaultPlayer, isPlayer: true);
    final participants = <RoleplayParticipant>[
      player,
      for (final participant in scenario.defaultParticipants)
        _copyParticipant(participant, isPlayer: false),
    ];
    final number = nextThreadIndex(scenarioId);
    final thread = RoleplayThread(
      id: threadId,
      scenarioId: scenario.id,
      title: '${scenario.title} #$number',
      scenarioTitle: scenario.title,
      scenario: scenario.scenario,
      director: scenario.director,
      participants: participants,
      groups: scenario.defaultGroups,
      playerParticipantId: player.id,
      maxAutoTurns: scenario.maxAutoTurns,
      createdAt: now,
      updatedAt: now,
    );
    _threads.add(thread);
    _touchScenario(scenario.id);
    _queueSave();
    notifyListeners();
    return threadId;
  }

  void deleteThread(String id) {
    final thread = getThread(id);
    final before = _threads.length;
    _threads.removeWhere((item) => item.id == id);
    if (_threads.length == before) return;
    _pendingPlayerMessagesByThread.remove(id);
    if (_activeThreadId == id) setRunState(RoleplayRunState.idle);
    if (thread != null) _touchScenario(thread.scenarioId);
    _queueSave();
    notifyListeners();
  }

  void renameThread(String id, String title) {
    final trimmed = title.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (trimmed.isEmpty) return;
    _updateThread(
      id,
      (thread) => thread.copyWith(title: trimmed, updatedAt: DateTime.now()),
    );
  }

  void updateThreadSettings(
    String id, {
    required String scenario,
    required RoleplayDirector director,
    required int maxAutoTurns,
  }) {
    _updateThread(
      id,
      (thread) => thread.copyWith(
        scenario: scenario.trim(),
        director: director,
        maxAutoTurns: maxAutoTurns < 0 ? 0 : maxAutoTurns,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void replaceThreadParticipants(
    String id, {
    required List<RoleplayParticipant> participants,
    required List<RoleplayParticipantGroup> groups,
    required String playerParticipantId,
  }) {
    _updateThread(
      id,
      (thread) => thread.copyWith(
        participants: participants,
        groups: groups,
        playerParticipantId: playerParticipantId,
        updatedAt: DateTime.now(),
      ),
    );
  }

  void appendPlayerMessage(
    String threadId,
    String content, {
    List<MessageImage> attachments = const [],
  }) {
    final thread = getThread(threadId);
    final player = thread?.player;
    if (thread == null || player == null) return;
    _appendMessage(
      threadId,
      RoleplayMessage(
        id: _uuid.v4(),
        speakerId: player.id,
        speakerName: player.name,
        content: content.trim(),
        kind: RoleplayMessageKind.player,
        attachments: attachments,
        timestamp: DateTime.now(),
      ),
    );
  }

  void queuePlayerMessage(
    String threadId,
    String content, {
    List<MessageImage> attachments = const [],
  }) {
    final trimmed = content.trim();
    if (trimmed.isEmpty && attachments.isEmpty) return;
    (_pendingPlayerMessagesByThread[threadId] ??= []).add(
      RoleplayQueuedPlayerMessage(trimmed, attachments),
    );
    notifyListeners();
  }

  RoleplayQueuedPlayerMessage? drainMergedPendingPlayerMessage(
    String threadId,
  ) {
    final messages = List<RoleplayQueuedPlayerMessage>.from(
      _pendingPlayerMessagesByThread[threadId] ?? const [],
    );
    _pendingPlayerMessagesByThread.remove(threadId);
    if (messages.isEmpty) return null;
    final content = messages
        .map((item) => item.content.trim())
        .where((item) => item.isNotEmpty)
        .join('\n\n');
    final attachments = <MessageImage>[];
    for (final item in messages) {
      attachments.addAll(item.attachments);
    }
    return RoleplayQueuedPlayerMessage(content, attachments);
  }

  void appendCharacterMessage(
    String threadId,
    RoleplayParticipant participant,
    String content,
  ) {
    _appendMessage(
      threadId,
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

  void appendNarratorMessage(String threadId, String content) {
    _appendMessage(
      threadId,
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

  void appendDraftAsCharacterMessage(
    String threadId,
    RoleplayParticipant participant,
  ) {
    final content = (_draftContent ?? '').trim();
    if (content.isEmpty) return;
    appendCharacterMessage(threadId, participant, content);
  }

  void setRunState(
    RoleplayRunState state, {
    String? threadId,
    String? speakerName,
    String? draftContent,
    String? errorMessage,
  }) {
    _runState = state;
    _activeThreadId = threadId;
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

  List<RoleplaySearchResult> search(String query) {
    final q = query.trim().toLowerCase();
    final results = <RoleplaySearchResult>[];
    for (final scenario in _sortedScenarios()) {
      final scenarioMatches =
          q.isEmpty ||
          scenario.title.toLowerCase().contains(q) ||
          scenario.scenario.toLowerCase().contains(q) ||
          scenario.description.toLowerCase().contains(q);
      final threadMatches = <RoleplaySearchResult>[];
      for (final thread in threadsForScenario(scenario.id)) {
        if (q.isEmpty) {
          threadMatches.add(
            RoleplaySearchResult(scenario: scenario, thread: thread),
          );
          continue;
        }
        if (thread.title.toLowerCase().contains(q)) {
          threadMatches.add(
            RoleplaySearchResult(
              scenario: scenario,
              thread: thread,
              matchInTitle: true,
            ),
          );
          continue;
        }
        for (final message in thread.messages) {
          final attachmentMatch = message.attachments.any(
            (item) => item.name.toLowerCase().contains(q),
          );
          if (message.content.toLowerCase().contains(q) || attachmentMatch) {
            threadMatches.add(
              RoleplaySearchResult(
                scenario: scenario,
                thread: thread,
                matchContent: message.content.isNotEmpty
                    ? message.content
                    : message.attachments.map((item) => item.name).join(', '),
              ),
            );
            break;
          }
        }
      }
      if (scenarioMatches || threadMatches.isNotEmpty) {
        results.add(
          RoleplaySearchResult(
            scenario: scenario,
            matchInTitle: scenario.title.toLowerCase().contains(q),
          ),
        );
        results.addAll(threadMatches);
      }
    }
    return results;
  }

  RoleplayParticipant participantFromChatRole(
    ChatRole role, {
    bool isPlayer = false,
    List<String> groupIds = const [],
  }) {
    return RoleplayParticipant(
      id: _uuid.v4(),
      sourceRoleId: role.id,
      name: role.name,
      description: role.description,
      systemPrompt: role.systemPrompt,
      model: RoleplayModelSelection(modelId: role.modelId),
      themeColor: role.themeColor?.toARGB32(),
      isPlayer: isPlayer,
      groupIds: groupIds,
    );
  }

  RoleplayParticipant customParticipant({
    required String name,
    String description = '',
    String systemPrompt = '',
    bool isPlayer = false,
    List<String> groupIds = const [],
  }) {
    return RoleplayParticipant(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? (isPlayer ? '我' : '角色') : name.trim(),
      description: description.trim(),
      systemPrompt: systemPrompt.trim().isEmpty
          ? description.trim()
          : systemPrompt.trim(),
      isPlayer: isPlayer,
      groupIds: groupIds,
    );
  }

  RoleplayParticipantGroup createLocalGroup(String name) {
    final now = DateTime.now();
    return RoleplayParticipantGroup(
      id: _uuid.v4(),
      name: name.trim().isEmpty ? '新分组' : name.trim(),
      createdAt: now,
      updatedAt: now,
    );
  }

  void _appendMessage(String threadId, RoleplayMessage message) {
    _updateThread(
      threadId,
      (thread) => thread.copyWith(
        messages: [...thread.messages, message],
        updatedAt: DateTime.now(),
      ),
    );
  }

  void _updateThread(
    String id,
    RoleplayThread Function(RoleplayThread) update,
  ) {
    final index = _threads.indexWhere((thread) => thread.id == id);
    if (index == -1) return;
    final updated = update(_threads[index]);
    _threads[index] = updated;
    _touchScenario(updated.scenarioId, notify: false);
    _queueSave();
    notifyListeners();
  }

  void _touchScenario(String id, {bool notify = true}) {
    final index = _scenarios.indexWhere((scenario) => scenario.id == id);
    if (index == -1) return;
    _scenarios[index] = _scenarios[index].copyWith(updatedAt: DateTime.now());
    if (notify) notifyListeners();
  }

  RoleplayParticipant _copyParticipant(
    RoleplayParticipant participant, {
    required bool isPlayer,
  }) {
    return participant.copyWith(id: _uuid.v4(), isPlayer: isPlayer);
  }

  List<RoleplayScenario> _sortedScenarios() {
    final list = List<RoleplayScenario>.from(_scenarios);
    list.sort((a, b) {
      if (a.pinned != b.pinned) return a.pinned ? -1 : 1;
      return b.updatedAt.compareTo(a.updatedAt);
    });
    return list;
  }

  List<RoleplayThread> _sortedThreads(List<RoleplayThread> source) {
    final list = List<RoleplayThread>.from(source);
    list.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    return list;
  }

  void _queueSave() {
    final scenarios = List<RoleplayScenario>.from(_scenarios);
    final threads = List<RoleplayThread>.from(_threads);
    _saveQueue = _saveQueue
        .then(
          (_) => _repository.save(
            scenarios: scenarios,
            threads: threads,
            usingStorageV2: _usingStorageV2,
          ),
        )
        .catchError((e) {
          debugPrint('保存情景演绎失败: $e');
        });
  }

  String _titleFromScenario(String scenario) {
    final clean = scenario.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (clean.isEmpty) return '情景演绎';
    return clean.length > 16 ? clean.substring(0, 16) : clean;
  }
}

class RoleplayQueuedPlayerMessage {
  final String content;
  final List<MessageImage> attachments;

  const RoleplayQueuedPlayerMessage(this.content, this.attachments);
}
