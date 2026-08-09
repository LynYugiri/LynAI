import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/chat_role.dart';
import '../models/agent_runtime.dart';
import '../models/agent_user_interaction.dart';
import '../models/app_settings.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../providers/conversation_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/knowledge_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import 'api_service.dart';
import 'agent_loop_runtime.dart';
import 'api_message_builder.dart';
import 'agent_persistence_lifecycle.dart';
import 'agent_tool_registry.dart';
import 'agent_tool_result_sanitizer.dart';
import 'agent_tool_execution_service.dart';
import 'agent_user_interaction_broker.dart';
import 'backend_client.dart';
import 'knowledge_annotation_prompt.dart';
import 'stream_chunk_agent_adapter.dart';
import 'storage_v2_service.dart';
import 'tool_call_service.dart';
import 'web_search_service.dart';

class FloatingChatSessionController extends ChangeNotifier {
  FloatingChatSessionController({
    required SettingsProvider settings,
    required ConversationProvider conversations,
    required ModelConfigProvider models,
    required FeatureProvider features,
    required KnowledgeProvider knowledge,
    required TaskProvider tasks,
    required CalendarProvider calendar,
    required PluginProvider plugins,
    AgentToolRegistry? externalToolRegistry,
    AgentRunPersistenceLifecycle? persistence,
    AgentToolResultProcessor? toolResultProcessor,
    AgentUserInteractionBroker? userInteractionBroker,
    StorageV2Service? storage,
    BackendClient? backend,
    WebSearchService? webSearch,
    ApiService? api,
  }) : _settings = settings,
       _conversations = conversations,
       _models = models,
       _features = features,
       _knowledge = knowledge,
       _tasks = tasks,
       _calendar = calendar,
       _plugins = plugins,
       _externalToolRegistry = externalToolRegistry,
       _persistence = persistence,
       _toolResultProcessor = toolResultProcessor,
       _userInteractionBroker =
           userInteractionBroker ?? AgentUserInteractionBroker(),
       _ownsUserInteractionBroker = userInteractionBroker == null,
       _api = api ?? ApiService(backend: backend),
       _ownsApi = api == null,
       _backend = backend {
    _storage = storage;
    _webSearch = webSearch;
    _userInteractionBroker.addListener(_onUserInteractionChanged);
  }

  static const _emptyAssistantReply = '模型没有返回内容，请稍后重试或检查模型配置。';

  final SettingsProvider _settings;
  final ConversationProvider _conversations;
  final ModelConfigProvider _models;
  final FeatureProvider _features;
  final KnowledgeProvider _knowledge;
  final TaskProvider _tasks;
  final CalendarProvider _calendar;
  final PluginProvider _plugins;
  final AgentToolRegistry? _externalToolRegistry;
  final AgentRunPersistenceLifecycle? _persistence;
  final AgentToolResultProcessor? _toolResultProcessor;
  final AgentUserInteractionBroker _userInteractionBroker;
  final bool _ownsUserInteractionBroker;
  final ApiService _api;
  final bool _ownsApi;
  final BackendClient? _backend;
  late final WebSearchService? _webSearch;
  late final StorageV2Service? _storage;

  StreamSubscription<AgentRunEvent>? _subscription;
  AgentRunHandle? _run;
  String? _runMessageId;
  String? _conversationId;
  String _draftContent = '';
  String _draftThinking = '';
  String _status = '';
  String _error = '';
  bool _streaming = false;
  int _generation = 0;

  String? get conversationId => _conversationId;
  ApiService get api => _api;
  bool get isStreaming => _streaming;
  bool get screenContextToolAllowed => _screenContextToolAllowed;
  AgentUserInteractionBroker get userInteractionBroker =>
      _userInteractionBroker;

  void startNewConversation() {
    if (_streaming) stop();
    _conversationId = null;
    _draftContent = '';
    _draftThinking = '';
    _status = '新对话已开始';
    _error = '';
    notifyListeners();
  }

  Map<String, dynamic> stateJson() {
    final conversation = _conversationId == null
        ? null
        : _conversations.getConversation(_conversationId!);
    final messages = conversation?.messages ?? const <Message>[];
    final annotationCategories = _knowledge.categories.where(
      (category) =>
          category.enabled &&
          category.autoAnnotate &&
          _knowledge.knowledgeBaseById(category.knowledgeBaseId)?.enabled ==
              true,
    );
    return {
      'conversationId': _conversationId,
      'title': conversation?.title ?? '悬浮对话',
      'streaming': _streaming,
      'status': _status,
      'error': _error,
      'draft': _draftContent,
      'thinking': _draftThinking,
      'fallbackKnowledgeCategory': _knowledge.annotationFallbackCategory?.id,
      'knowledgeCategories': {
        for (final category in annotationCategories) ...{
          category.id: {'id': category.id, 'colorValue': category.colorValue},
          category.alias: {
            'id': category.id,
            'colorValue': category.colorValue,
          },
        },
      },
      'screenContextEnabled': _screenContextToolAllowed,
      if (_pendingUserInteraction != null)
        'pendingUserInteraction': _pendingUserInteraction!.toJson(),
      'messages': messages
          .where((message) => message.agentTrace == null)
          .take(40)
          .map(
            (message) => {
              'id': message.id,
              'role': message.role,
              'content': message.content,
              if (message.thinkingContent != null)
                'thinking': message.thinkingContent,
            },
          )
          .toList(growable: false),
    };
  }

  AgentUserInteractionResponseStatus answerUserInteraction({
    required String requestId,
    required AgentUserAnswer answer,
  }) {
    return _userInteractionBroker.answer(
      surface: AgentUserInteractionSurface.floatingAssistant,
      requestId: requestId,
      answer: answer,
    );
  }

  AgentUserInteractionResponseStatus cancelUserInteraction({
    required String requestId,
    String? reason,
  }) {
    return _userInteractionBroker.cancel(
      surface: AgentUserInteractionSurface.floatingAssistant,
      requestId: requestId,
      reason: reason,
    );
  }

  Future<void> send(String rawText) async {
    final text = rawText.trim();
    if (text.isEmpty || _streaming) return;
    _clearTransientStatus();
    final model = _currentModel();
    if (model == null) {
      _setError('请先在设置中添加 AI 模型');
      return;
    }

    final settings = _conversationSettings(model);
    final annotationPrompt = const KnowledgeAnnotationPromptFormatter().format(
      _knowledge.knowledgeAnnotationPromptSnapshot,
    );
    final roleId = _settings.settings.currentRoleId;
    final isNewConversation = _conversationId == null;
    if (isNewConversation) {
      _conversationId = _conversations.createConversationWithMessages(
        settings,
        roleId: roleId,
        messages: [
          (role: 'user', content: text, images: const <MessageImage>[]),
          (role: 'assistant', content: '', images: const <MessageImage>[]),
        ],
      );
    } else {
      _conversations.addMessage(_conversationId!, 'user', text);
      _conversations.addMessage(_conversationId!, 'assistant', '', save: false);
    }

    _streaming = true;
    _status = '正在生成...';
    _draftContent = '';
    _draftThinking = '';
    notifyListeners();

    final conversation = _conversations.getConversation(_conversationId!);
    if (conversation == null) return;
    final messages = buildApiMessages(
      conversation,
      _plugins.plugins,
      enableTools: _supportsNativeTools(model),
      annotationPrompt: annotationPrompt,
      extraSystemPrompt: _screenContextToolAllowed
          ? '悬浮聊天已获得用户授权：当用户问题依赖当前 Android 前台页面时，可以调用 get_current_screen 读取可见文本和节点摘要。不要无故读取。'
          : '',
    );
    unawaited(
      _streamTurn(
        model,
        _conversationId!,
        messages,
        createTitle: isNewConversation,
        allowTools: _supportsNativeTools(model),
      ),
    );
  }

  void stop() {
    _userInteractionBroker.cancelSurface(
      AgentUserInteractionSurface.floatingAssistant,
      reason: 'user_stopped',
    );
    if (!_streaming) return;
    _generation++;
    final run = _run;
    final messageId = _runMessageId;
    run?.cancel();
    _run = null;
    _runMessageId = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final conversationId = _conversationId;
    _streaming = false;
    _status = '已停止生成';
    if (conversationId != null && run != null && messageId != null) {
      unawaited(
        run.result.then((result) {
          final partial = result.partialContent.trim();
          _conversations.updateMessageContent(
            conversationId,
            messageId,
            partial.isEmpty ? '已停止生成' : '$partial\n\n---\n已停止生成',
            thinkingContent: result.reasoning,
          );
        }),
      );
    }
    notifyListeners();
  }

  Future<Map<String, dynamic>> transcribeAudioPath(String path) async {
    if (path.trim().isEmpty) return {'ok': false, 'error': '录音文件路径为空'};
    final speechModelId = _activeSpeechModelId;
    if (speechModelId == null || speechModelId.isEmpty) {
      return {'ok': false, 'error': '请先在设置中选择语音转文字模型'};
    }
    final speechConfig = _findModel(_models.models, speechModelId);
    if (speechConfig == null) {
      return {'ok': false, 'error': '语音转文字接口不存在，请在设置中重新选择'};
    }
    final file = File(path);
    try {
      if (!await file.exists()) {
        return {'ok': false, 'error': '录音文件已不存在'};
      }
      final text = await _api.transcribeAudio(
        speechConfig,
        await file.readAsBytes(),
      );
      return {'ok': true, 'text': text};
    } catch (e) {
      return {
        'ok': false,
        'error': e.toString().replaceFirst('Exception: ', ''),
      };
    } finally {
      try {
        await file.delete();
      } on FileSystemException {
        // Best-effort cleanup for native recorder temp files.
      }
    }
  }

  @override
  Future<void> dispose() async {
    await _subscription?.cancel();
    _subscription = null;
    _run?.cancel();
    _userInteractionBroker.removeListener(_onUserInteractionChanged);
    _userInteractionBroker.cancelSurface(
      AgentUserInteractionSurface.floatingAssistant,
      reason: 'floating_chat_disposed',
    );
    if (_ownsUserInteractionBroker) {
      _userInteractionBroker.dispose();
    }
    if (_ownsApi) _api.dispose();
    super.dispose();
  }

  AgentUserInteractionRequest? get _pendingUserInteraction =>
      _userInteractionBroker.pendingFor(
        AgentUserInteractionSurface.floatingAssistant,
      );

  void _onUserInteractionChanged() {
    notifyListeners();
  }

  ModelConfig? _currentModel() {
    final chatModels = _models.enabledModelsByCategory(
      ModelConfig.categoryChat,
    );
    if (chatModels.isEmpty) return null;
    final conversationId = _conversationId;
    if (conversationId != null) {
      final conversation = _conversations.getConversation(conversationId);
      if (conversation != null) {
        final model = _findModel(chatModels, conversation.modelId);
        if (model != null) {
          final modelName = conversation.settings.modelName;
          return modelName == null || modelName.isEmpty
              ? model
              : model.copyWith(modelName: modelName);
        }
      }
    }

    final role = _settings.currentRole;
    final roleModelId = role.modelId;
    if (roleModelId != null && roleModelId.isNotEmpty) {
      final model = _findModel(chatModels, roleModelId);
      if (model != null) {
        final modelName = role.modelName;
        return modelName == null || modelName.isEmpty
            ? model
            : model.copyWith(modelName: modelName);
      }
    }

    final lastChatModelId = _settings.settings.lastChatModelId;
    if (lastChatModelId != null && lastChatModelId.isNotEmpty) {
      final model = _findModel(chatModels, lastChatModelId);
      if (model != null) return model;
    }
    return chatModels.first;
  }

  String? get _activeSpeechModelId {
    final conversationId = _conversationId;
    if (conversationId != null) {
      final conversation = _conversations.getConversation(conversationId);
      final id = conversation?.settings.speechModelId;
      if (id != null && id.isNotEmpty) return id;
    }
    return _settings.settings.speechModelId;
  }

  ConversationSettings _conversationSettings(ModelConfig model) {
    final appSettings = _settings.settings;
    final role = _settings.currentRole;
    if (role.id != ChatRole.defaultId || role.modelId != null) {
      return ConversationSettings(
        modelId: role.modelId ?? model.id,
        modelName: role.modelName ?? model.modelName,
        thinking: model.supportsThinking,
        selectedSystemPromptId: role.id == ChatRole.defaultId ? null : role.id,
        systemPrompt: role.systemPrompt,
        speechModelId: appSettings.speechModelId,
        imageModelId: appSettings.imageModelId,
        imageOcrEnabled: appSettings.imageOcrEnabled,
        imageRecognitionModelId: appSettings.imageRecognitionModelId,
        imageRecognitionEnabled: appSettings.imageRecognitionEnabled,
        imageRecognitionPrompt: appSettings.imageRecognitionPrompt,
        imageGenerationModelId: appSettings.imageGenerationModelId,
        imageGenerationEnabled: appSettings.imageGenerationEnabled,
        agentEnabled: appSettings.agentEnabledByDefault,
        agentGrantedPermissions: appSettings.agentGrantedPermissions,
      );
    }
    return ConversationSettings(
      modelId: model.id,
      modelName: model.modelName,
      thinking: model.supportsThinking,
      selectedSystemPromptId: appSettings.selectedSystemPromptId,
      systemPrompt: _settings.effectiveSystemPrompt,
      speechModelId: appSettings.speechModelId,
      imageModelId: appSettings.imageModelId,
      imageOcrEnabled: appSettings.imageOcrEnabled,
      imageRecognitionModelId: appSettings.imageRecognitionModelId,
      imageRecognitionEnabled: appSettings.imageRecognitionEnabled,
      imageRecognitionPrompt: appSettings.imageRecognitionPrompt,
      imageGenerationModelId: appSettings.imageGenerationModelId,
      imageGenerationEnabled: appSettings.imageGenerationEnabled,
      agentEnabled: appSettings.agentEnabledByDefault,
      agentGrantedPermissions: appSettings.agentGrantedPermissions,
    );
  }

  Future<void> _streamTurn(
    ModelConfig model,
    String conversationId,
    List<Map<String, dynamic>> working, {
    required bool createTitle,
    required bool allowTools,
  }) async {
    final generation = ++_generation;
    bool webSearchConfigured = false;
    try {
      webSearchConfigured =
          await (_webSearch?.isConfigured() ?? Future.value(false));
    } catch (error) {
      debugPrint('查询网页搜索配置失败，按未配置处理: $error');
    }
    if (generation != _generation || !_streaming) {
      final last = _conversations
          .getConversation(conversationId)
          ?.messages
          .lastOrNull;
      if (last != null && last.role == 'assistant' && last.content.isEmpty) {
        _conversations.updateMessageContent(conversationId, last.id, '已停止生成');
      }
      return;
    }
    final screenContextEnabled = _screenContextToolAllowed;
    final conversationSettings = _conversations
        .getConversation(conversationId)
        ?.settings;
    var buffer = '';
    var thinkingBuffer = '';
    final externalToolSnapshot = _externalToolRegistry?.snapshot();
    _runMessageId = _conversations
        .getConversation(conversationId)
        ?.messages
        .lastOrNull
        ?.id;
    final toolService = ToolCallService(
      _features,
      tasks: _tasks,
      calendar: _calendar,
      knowledge: _knowledge,
      plugins: _plugins,
      modelConfigs: _models,
      settings: _settings,
      conversations: _conversations,
      backend: _backend,
      conversationId: conversationId,
      persistence: _persistence,
      allowScreenContextTool: screenContextEnabled,
      externalToolRegistry: _externalToolRegistry,
      externalToolSnapshot: externalToolSnapshot,
      storage: _storage,
      resultSanitizer: _storage == null
          ? null
          : AgentToolResultSanitizer.storageV2(_storage),
      toolResultProcessor: _toolResultProcessor,
      userInteractionBroker: _userInteractionBroker,
      interactionSurface: AgentUserInteractionSurface.floatingAssistant,
      webSearch: _webSearch,
      webSearchConfigured: webSearchConfigured,
      permissionSnapshot: conversationSettings?.inheritsAgentPermissions == true
          ? _settings.settings.agentPermissionSnapshot
          : conversationSettings?.permissionSnapshot,
    );
    final runSnapshot = toolService.createRunSnapshot(
      agentEnabled: conversationSettings?.agentEnabled == true,
      imageGenerationEnabled:
          conversationSettings?.imageGenerationEnabled == true,
    );
    final tools = allowTools
        ? runSnapshot.openAITools
        : const <Map<String, dynamic>>[];
    final run = const AgentLoopRuntime().start(
      messages: working,
      maxToolRounds: ToolCallService.maxToolRounds,
      persistence: _persistence,
      toolResultProcessor: _toolResultProcessor,
      persistenceMetadata: AgentRunPersistenceMetadata(
        conversationId: conversationId,
        permissionPolicy: conversationSettings?.inheritsAgentPermissions == true
            ? _settings.settings.agentPermissionSnapshot
            : conversationSettings?.permissionSnapshot,
      ),
      model: (request) => const StreamChunkAgentAdapter().adapt(
        _api.sendStreamRequest(
          model,
          request.messages,
          thinking:
              conversationSettings?.thinking == true && model.supportsThinking,
          tools: request.forceFinalResponse ? const [] : tools,
          toolChoice: request.forceFinalResponse ? null : 'auto',
        ),
      ),
      executeTools: (calls, identity, cancellationToken) {
        return toolService.executeCapturedBatch(
          runSnapshot,
          calls,
          identity: identity,
          cancellationToken: cancellationToken,
        );
      },
      datasetBarrier: _storage?.runtimeBarrier,
    );
    _run = run;
    unawaited(_subscription?.cancel());
    _subscription = run.events.listen((event) {
      if (generation != _generation || event.runId != run.id) return;
      switch (event.kind) {
        case AgentRunEventKind.turnStarted:
          buffer = '';
          thinkingBuffer = '';
        case AgentRunEventKind.textDelta:
          buffer += event.text ?? '';
          _draftContent = buffer;
          _status = '正在生成...';
          notifyListeners();
        case AgentRunEventKind.reasoningDelta:
          thinkingBuffer += event.text ?? '';
          _draftThinking = thinkingBuffer;
          _status = buffer.isEmpty ? '正在等待模型...' : '正在生成...';
          notifyListeners();
        case AgentRunEventKind.toolCalls:
          _status = '正在调用工具...';
          notifyListeners();
        default:
          break;
      }
    });
    unawaited(
      run.result.then((result) {
        if (generation != _generation || result.runId != run.id) return;
        _run = null;
        _runMessageId = null;
        if (result.isCancelled) return;
        if (!result.isSuccess) {
          _streaming = false;
          _draftContent = '';
          _draftThinking = '';
          final error = result.error.toString().replaceFirst('Exception: ', '');
          _setError(error);
          final partial = result.partialContent.trim();
          _conversations.updateLastMessage(
            conversationId,
            partial.isEmpty ? '请求失败: $error' : '$partial\n\n---\n请求失败: $error',
            thinkingContent: result.reasoning,
          );
          return;
        }
        final content = result.toolRoundLimitReached
            ? ToolCallService.toolRoundLimitMessage(result.content)
            : result.content.trim().isEmpty
            ? _emptyAssistantReply
            : result.content;
        _streaming = false;
        _status = '';
        _draftContent = '';
        _draftThinking = '';
        _conversations.updateLastMessage(
          conversationId,
          content,
          thinkingContent: result.reasoning,
        );
        if (createTitle) {
          unawaited(_maybeCreateConversationTitle(model, conversationId));
        }
        notifyListeners();
      }),
    );
  }

  Future<void> _maybeCreateConversationTitle(
    ModelConfig model,
    String conversationId,
  ) async {
    final conversation = _conversations.getConversation(conversationId);
    if (conversation == null ||
        conversation.messages
                .where((message) => message.role == 'user')
                .length !=
            1) {
      return;
    }
    final firstUser = conversation.messages.firstWhere(
      (message) => message.role == 'user',
    );
    try {
      final response = await _api.sendChatRequest(model, [
        {
          'role': 'system',
          'content': '根据用户第一条消息创建一个简短中文对话标题，只返回标题本身，最多 16 个字。',
        },
        {'role': 'user', 'content': firstUser.content},
      ], thinking: false);
      final title = response.content
          .replaceAll(RegExp(r'[\r\n"“”]'), '')
          .trim();
      if (title.isNotEmpty) {
        _conversations.updateConversationTitle(
          conversationId,
          title.length > 24 ? title.substring(0, 24) : title,
        );
        notifyListeners();
      }
    } catch (_) {}
  }

  bool _supportsNativeTools(ModelConfig model) => model.supportsNativeTools;

  bool get _screenContextToolAllowed {
    final floating = _settings.settings.floatingAssistant;
    return floating.allowScreenContext &&
        floating.screenContextMode !=
            FloatingAssistantSettings.screenContextDisabled;
  }

  ModelConfig? _findModel(List<ModelConfig> models, String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  void _clearTransientStatus() {
    _error = '';
    _status = '';
  }

  void _setError(String message) {
    _error = message;
    _status = '';
    notifyListeners();
  }
}
