import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';

import '../models/chat_role.dart';
import '../models/agent_runtime.dart';
import '../models/app_settings.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../providers/conversation_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import 'api_service.dart';
import 'agent_loop_runtime.dart';
import 'agent_persistence_lifecycle.dart';
import 'agent_tool_registry.dart';
import 'backend_client.dart';
import 'stream_chunk_agent_adapter.dart';
import 'tool_call_service.dart';

class FloatingChatSessionController extends ChangeNotifier {
  FloatingChatSessionController({
    required SettingsProvider settings,
    required ConversationProvider conversations,
    required ModelConfigProvider models,
    required FeatureProvider features,
    required TaskProvider tasks,
    required CalendarProvider calendar,
    required PluginProvider plugins,
    AgentToolRegistry? externalToolRegistry,
    AgentRunPersistenceLifecycle? persistence,
    BackendClient? backend,
    ApiService? api,
  }) : _settings = settings,
       _conversations = conversations,
       _models = models,
       _features = features,
       _tasks = tasks,
       _calendar = calendar,
       _plugins = plugins,
       _externalToolRegistry = externalToolRegistry,
       _persistence = persistence,
       _api = api ?? ApiService(backend: backend),
       _ownsApi = api == null,
       _backend = backend;

  static const _emptyAssistantReply = '模型没有返回内容，请稍后重试或检查模型配置。';
  static const _maxToolDepth = 6;

  final SettingsProvider _settings;
  final ConversationProvider _conversations;
  final ModelConfigProvider _models;
  final FeatureProvider _features;
  final TaskProvider _tasks;
  final CalendarProvider _calendar;
  final PluginProvider _plugins;
  final AgentToolRegistry? _externalToolRegistry;
  final AgentRunPersistenceLifecycle? _persistence;
  final ApiService _api;
  final bool _ownsApi;
  final BackendClient? _backend;

  StreamSubscription<AgentRunEvent>? _subscription;
  AgentRunHandle? _run;
  String? _conversationId;
  String _draftContent = '';
  String _draftThinking = '';
  String _status = '';
  String _error = '';
  bool _streaming = false;
  int _generation = 0;

  String? get conversationId => _conversationId;
  bool get isStreaming => _streaming;
  bool get screenContextToolAllowed => _screenContextToolAllowed;

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
    return {
      'conversationId': _conversationId,
      'title': conversation?.title ?? '悬浮对话',
      'streaming': _streaming,
      'status': _status,
      'error': _error,
      'draft': _draftContent,
      'thinking': _draftThinking,
      'screenContextEnabled': _screenContextToolAllowed,
      'messages': messages
          .where((message) => message.agentTrace == null)
          .take(40)
          .map(
            (message) => {
              'role': message.role,
              'content': message.content,
              if (message.thinkingContent != null)
                'thinking': message.thinkingContent,
            },
          )
          .toList(growable: false),
    };
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
    final messages = _buildApiMessages(
      conversation,
      enableTools: _supportsNativeTools(model),
    );
    _streamTurn(
      model,
      _conversationId!,
      messages,
      createTitle: isNewConversation,
      allowTools: _supportsNativeTools(model),
    );
  }

  void stop() {
    if (!_streaming) return;
    _generation++;
    _run?.cancel();
    _run = null;
    unawaited(_subscription?.cancel());
    _subscription = null;
    final conversationId = _conversationId;
    _streaming = false;
    _status = '已停止生成';
    if (conversationId != null) {
      final conversation = _conversations.getConversation(conversationId);
      if (conversation != null && conversation.messages.isNotEmpty) {
        final last = conversation.messages.last;
        if (last.role == 'assistant' && last.content.trim().isEmpty) {
          _conversations.updateLastMessage(conversationId, '已停止生成');
        } else if (last.role == 'assistant') {
          _conversations.updateLastMessage(
            conversationId,
            '${last.content}\n\n---\n已停止生成',
          );
        }
      }
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
    if (_ownsApi) _api.dispose();
    super.dispose();
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
        thinking: true,
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
      );
    }
    return ConversationSettings(
      modelId: model.id,
      modelName: model.modelName,
      thinking: true,
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
    );
  }

  List<Map<String, dynamic>> _buildApiMessages(
    Conversation conversation, {
    required bool enableTools,
  }) {
    final messages = <Map<String, dynamic>>[];
    final promptContent = conversation.settings.systemPrompt;
    final toolPrompt = conversation.settings.agentEnabled
        ? '${ToolCallService.nativeSystemPrompt}\n\n${ToolCallService.agentSystemPromptWithSkills(_plugins.plugins)}'
        : ToolCallService.nativeSystemPrompt;
    final agentContext = conversation.settings.agentEnabled
        ? ToolCallService.agentContextPrompt(conversation)
        : '';
    final screenPrompt = _screenContextToolAllowed
        ? '悬浮聊天已获得用户授权：当用户问题依赖当前 Android 前台页面时，可以调用 get_current_screen 读取可见文本和节点摘要。不要无故读取。'
        : '';
    final fullToolPrompt = [
      toolPrompt,
      if (agentContext.isNotEmpty) agentContext,
      if (screenPrompt.isNotEmpty) screenPrompt,
    ].join('\n\n');
    if (promptContent.isNotEmpty) {
      messages.add({
        'role': 'system',
        'content': enableTools
            ? '$promptContent\n\n$fullToolPrompt\n\n${ToolCallService.currentTimeContext()}'
            : promptContent,
      });
    } else if (enableTools) {
      messages.add({
        'role': 'system',
        'content': '$fullToolPrompt\n\n${ToolCallService.currentTimeContext()}',
      });
    }
    for (final message in conversation.messages) {
      if (message.role == 'assistant' && message.content.isEmpty) continue;
      messages.add({
        'role': message.role,
        'content': message.content,
        if (message.role == 'assistant') 'reasoning_content': '',
      });
    }
    return messages;
  }

  void _streamTurn(
    ModelConfig model,
    String conversationId,
    List<Map<String, dynamic>> working, {
    required bool createTitle,
    required bool allowTools,
  }) {
    final generation = ++_generation;
    final screenContextEnabled = _screenContextToolAllowed;
    final conversationSettings = _conversations
        .getConversation(conversationId)
        ?.settings;
    var buffer = '';
    var thinkingBuffer = '';
    final externalToolSnapshot = _externalToolRegistry?.snapshot();
    final tools = allowTools
        ? ToolCallService.openAITools(
            _plugins.plugins,
            conversationSettings?.agentEnabled == true,
            _settings.settings.agentGrantedPermissions,
            conversationSettings?.imageGenerationEnabled == true,
            screenContextEnabled,
            externalToolSnapshot,
          )
        : const <Map<String, dynamic>>[];
    final toolService = ToolCallService(
      _features,
      tasks: _tasks,
      calendar: _calendar,
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
    );
    final run = const AgentLoopRuntime().start(
      messages: working,
      maxToolRounds: _maxToolDepth,
      persistence: _persistence,
      persistenceMetadata: AgentRunPersistenceMetadata(
        conversationId: conversationId,
      ),
      model: (request) => const StreamChunkAgentAdapter().adapt(
        _api.sendStreamRequest(
          model,
          request.messages,
          thinking: model.supportsThinking,
          tools: request.forceFinalResponse ? const [] : tools,
          toolChoice: request.forceFinalResponse ? null : 'auto',
        ),
      ),
      executeTools: (calls, identity, cancellationToken) {
        final conversation = _conversations.getConversation(conversationId);
        return toolService.executeSequentialCompatibility(
          calls,
          conversation?.messages ?? const [],
          identity: identity,
          cancellationToken: cancellationToken,
        );
      },
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
        if (result.isCancelled) return;
        if (!result.isSuccess) {
          _streaming = false;
          _draftContent = '';
          _draftThinking = '';
          final error = result.error.toString().replaceFirst('Exception: ', '');
          _setError(error);
          _conversations.updateLastMessage(
            conversationId,
            buffer.isEmpty ? '请求失败: $error' : '$buffer\n\n---\n请求失败: $error',
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
