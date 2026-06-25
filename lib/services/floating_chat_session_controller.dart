import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/chat_role.dart';
import '../models/app_settings.dart';
import '../models/conversation.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import 'api_service.dart';
import 'device_control_service.dart';
import 'floating_assistant_bridge.dart';
import 'tool_call_service.dart';

class FloatingChatSessionController {
  FloatingChatSessionController({
    required SettingsProvider settings,
    required ConversationProvider conversations,
    required ModelConfigProvider models,
    required FeatureProvider features,
    required PluginProvider plugins,
    required VoidCallback onChanged,
  }) : _settings = settings,
       _conversations = conversations,
       _models = models,
       _features = features,
       _plugins = plugins,
       _onChanged = onChanged;

  static const _emptyAssistantReply = '模型没有返回内容，请稍后重试或检查模型配置。';
  static const _maxToolDepth = 6;
  static const _translationHistoryKey = 'floating_translation_history';
  static const _maxHistoryEntries = 20;
  static const _maxOverlayBlocks = 30;

  static const _languageNames = <String, String>{
    'zh-CN': '简体中文',
    'zh-TW': '繁體中文',
    'en': 'English',
    'ja': '日本語',
    'ko': '한국어',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
    'ru': 'Русский',
    'pt': 'Português',
    'it': 'Italiano',
    'th': 'ไทย',
    'vi': 'Tiếng Việt',
    'ar': 'العربية',
  };

  final SettingsProvider _settings;
  final ConversationProvider _conversations;
  final ModelConfigProvider _models;
  final FeatureProvider _features;
  final PluginProvider _plugins;
  final VoidCallback _onChanged;
  final ApiService _api = ApiService();

  StreamSubscription<StreamChunk>? _subscription;
  String? _conversationId;
  String _draftContent = '';
  String _draftThinking = '';
  String _status = '';
  String _error = '';
  String _translationText = '';
  bool _streaming = false;
  int _generation = 0;

  final Map<String, String> _translatedCache = {};
  final List<Map<String, dynamic>> _translationHistory = [];
  bool _translationOverlayActive = false;

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
    _onChanged();
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
      'translationText': _translationText,
      'translationHistory': _translationHistory.take(5).toList(),
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
    _onChanged();

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
      depth: 0,
      priorThinking: null,
    );
  }

  void stop() {
    if (!_streaming) return;
    _generation++;
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
    _onChanged();
  }

  Future<void> translateCurrentScreen() async {
    if (_streaming) return;
    _clearTransientStatus();
    _status = '正在读取当前页面...';
    _translatedCache.clear();
    _onChanged();
    final floating = _settings.settings.floatingAssistant;
    final targetLanguage = _languageNames[floating.mangaTargetLanguage] ?? '简体中文';
    final blocks = await _extractTextBlocks();
    if (blocks.isEmpty) {
      _setError('当前页面没有可读取文本');
      return;
    }
    final model = _currentModel();
    if (model == null) {
      _setError('请先在设置中添加 AI 模型');
      return;
    }
    _translationOverlayActive = true;
    _status = '正在翻译...';
    _onChanged();
    await _batchTranslateAndOverlay(model, blocks, targetLanguage);
  }

  Future<void> onTranslationScrollSettled() async {
    if (!_translationOverlayActive || _streaming) return;
    final floating = _settings.settings.floatingAssistant;
    final targetLanguage = _languageNames[floating.mangaTargetLanguage] ?? '简体中文';
    final blocks = await _extractTextBlocks();
    if (blocks.isEmpty) return;
    final newBlocks = blocks.where((b) => !_translatedCache.containsKey(b['id'])).toList();
    final cachedBlocks = blocks.where((b) => _translatedCache.containsKey(b['id'])).toList();
    final allBlocks = <Map<String, dynamic>>[];
    for (final b in cachedBlocks) {
      allBlocks.add({
        ...b,
        'translatedText': _translatedCache[b['id']],
      });
    }
    if (newBlocks.isNotEmpty) {
      final model = _currentModel();
      if (model == null) return;
      final translations = await _batchTranslate(model, newBlocks, targetLanguage);
      for (final b in newBlocks) {
        final translated = translations[b['id']] ?? '';
        if (translated.isNotEmpty) {
          _translatedCache[b['id']] = translated;
          allBlocks.add({...b, 'translatedText': translated});
        }
      }
    }
    _updateOverlay(allBlocks, floating);
    _onChanged();
  }

  Future<List<Map<String, dynamic>>> _extractTextBlocks() async {
    // OCR-first: screenshot → PPOCRv5 ncnn OCR.
    // Accessibility snapshot is the fallback for pure-text UIs (chat apps,
    // browsers) where OCR may struggle but the accessibility tree has exact
    // text + bounds.
    final ocrBlocks = await _extractOcrBlocks();
    if (ocrBlocks.isNotEmpty) return ocrBlocks.take(_maxOverlayBlocks).toList();

    final snapshot = await DeviceControlService.instance.execute(
      'device.screen.snapshot',
      const {},
    );
    if (snapshot['ok'] != true) return const [];
    final result = snapshot['result'];
    if (result is! Map) return const [];
    final packageName = result['packageName']?.toString() ?? '';
    final roots = (result['roots'] as List?) ?? const [];
    final blocks = <Map<String, dynamic>>[];
    for (final root in roots) {
      if (root is Map) {
        _collectTextBlocks(root, blocks, packageName);
      }
    }
    return blocks.take(_maxOverlayBlocks).toList();
  }

  void _collectTextBlocks(
    Map node,
    List<Map<String, dynamic>> blocks,
    String packageName,
  ) {
    final text = node['text']?.toString().trim() ?? '';
    final bounds = node['bounds'];
    if (text.isNotEmpty && bounds is Map && !_isLikelyUiLabel(text)) {
      final left = (bounds['left'] as num?)?.toInt() ?? 0;
      final top = (bounds['top'] as num?)?.toInt() ?? 0;
      final right = (bounds['right'] as num?)?.toInt() ?? 0;
      final bottom = (bounds['bottom'] as num?)?.toInt() ?? 0;
      if (right > left && bottom > top) {
        blocks.add({
          'id': '${text.hashCode}_${left}_$top',
          'originalText': text,
          'bounds': {'left': left, 'top': top, 'right': right, 'bottom': bottom},
          'packageName': packageName,
        });
      }
    }
    final children = (node['children'] as List?) ?? const [];
    for (final child in children) {
      if (child is Map) _collectTextBlocks(child, blocks, packageName);
    }
  }

  bool _isLikelyUiLabel(String text) {
    if (text.length <= 2) return true;
    final uiLabels = {'确定', '取消', '返回', '关闭', '搜索', '更多', '设置', '分享', '编辑', '删除', 'OK', 'ok'};
    if (uiLabels.contains(text)) return true;
    return false;
  }

  Future<List<Map<String, dynamic>>> _extractOcrBlocks() async {
    final screenshot = await DeviceControlService.instance.execute(
      'device.screen.screenshot',
      const {},
    );
    if (screenshot['ok'] != true) return const [];
    final result = screenshot['result'];
    if (result is! Map) return const [];
    final dataBase64 = result['dataBase64']?.toString() ?? '';
    if (dataBase64.isEmpty) return const [];
    final ocr = await DeviceControlService.instance.execute(
      'device.screen.ocr',
      {'imageBase64': dataBase64},
    );
    if (ocr['ok'] != true) return const [];
    final blocks = (ocr['result'] as List?) ?? const [];
    return blocks.cast<Map>()
        .where((b) {
          final text = b['text']?.toString().trim() ?? '';
          return text.isNotEmpty && !_isLikelyUiLabel(text);
        })
        .map((b) {
      final bounds = (b['bounds'] as Map?) ?? {};
      return <String, dynamic>{
        'id': b['id']?.toString() ?? 'ocr_${blocks.indexOf(b)}',
        'originalText': b['text']?.toString() ?? '',
        'bounds': {
          'left': (bounds['left'] as num?)?.toInt() ?? 0,
          'top': (bounds['top'] as num?)?.toInt() ?? 0,
          'right': (bounds['right'] as num?)?.toInt() ?? 0,
          'bottom': (bounds['bottom'] as num?)?.toInt() ?? 0,
        },
        'orientation': b['orientation'] ?? 0,
        'packageName': '',
      };
    }).toList();
  }

  Future<void> _batchTranslateAndOverlay(
    ModelConfig model,
    List<Map<String, dynamic>> blocks,
    String targetLanguage,
  ) async {
    try {
      final packageName = blocks.first['packageName']?.toString() ?? '';
      final systemPrompt = _buildTranslationPrompt(targetLanguage, packageName);
      final userContent = blocks
          .asMap()
          .entries
          .map((e) => '[${e.key}] ${e.value['originalText']}')
          .join('\n');
      final stream = _api.sendStreamRequest(
        model,
        [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        thinking: false,
      );
      var fullResponse = '';
      _subscription?.cancel();
      _subscription = stream.listen(
        (chunk) {
          if (chunk.content != null) fullResponse += chunk.content!;
          _translationText = fullResponse;
          _status = '正在翻译...';
          _onChanged();
        },
        onError: (Object error) {
          _setError('翻译失败: $error');
          _translationOverlayActive = false;
        },
        onDone: () {
          _parseAndApplyTranslations(fullResponse, blocks, targetLanguage);
        },
      );
    } catch (e) {
      _setError('翻译失败: $e');
      _translationOverlayActive = false;
    }
  }

  Future<Map<String, String>> _batchTranslate(
    ModelConfig model,
    List<Map<String, dynamic>> blocks,
    String targetLanguage,
  ) async {
    try {
      final packageName = blocks.first['packageName']?.toString() ?? '';
      final systemPrompt = _buildTranslationPrompt(targetLanguage, packageName);
      final userContent = blocks
          .asMap()
          .entries
          .map((e) => '[${e.key}] ${e.value['originalText']}')
          .join('\n');
      final response = await _api.sendChatRequest(
        model,
        [
          {'role': 'system', 'content': systemPrompt},
          {'role': 'user', 'content': userContent},
        ],
        thinking: false,
      );
      return _parseTranslations(response.content, blocks);
    } catch (_) {
      return {};
    }
  }

  String _buildTranslationPrompt(String targetLanguage, String packageName) {
    final contextHint = packageName.isNotEmpty ? '当前页面来自应用: $packageName。' : '';
    return '你是屏幕文本翻译助手。$contextHint'
        '将用户提供的文本翻译成$targetLanguage。'
        '如果文本已经是$targetLanguage，则原样返回。'
        '用户会提供多段文本，每段前有 [序号] 标记。'
        '部分文本可能来自竖排文字（如漫画），其中的换行符表示竖排阅读顺序，翻译时请保持自然语序。'
        '请以 JSON 数组格式返回翻译结果，每个元素包含 "index" 和 "translation" 字段。'
        '只输出 JSON，不要额外解释。'
        '保留原始分段，不要合并或拆分文本块。';
  }

  void _parseAndApplyTranslations(
    String response,
    List<Map<String, dynamic>> blocks,
    String targetLanguage,
  ) {
    final translations = _parseTranslations(response, blocks);
    final allBlocks = <Map<String, dynamic>>[];
    for (final block in blocks) {
      final translated = translations[block['id']] ?? '';
      if (translated.isNotEmpty) {
        _translatedCache[block['id']] = translated;
        allBlocks.add({...block, 'translatedText': translated});
      }
    }
    final floating = _settings.settings.floatingAssistant;
    _updateOverlay(allBlocks, floating);
    _translationText = allBlocks
        .map((b) => b['translatedText']?.toString() ?? '')
        .where((t) => t.isNotEmpty)
        .join('\n');
    _status = allBlocks.isEmpty ? '未获得译文' : '已翻译当前页面';
    _saveToHistory(allBlocks);
    _onChanged();
  }

  Map<String, String> _parseTranslations(
    String response,
    List<Map<String, dynamic>> blocks,
  ) {
    final result = <String, String>{};
    try {
      String json = response.trim();
      if (json.startsWith('```')) {
        json = json.replaceAll(RegExp(r'^```(?:json)?\n?'), '').replaceAll(RegExp(r'\n?```$'), '');
      }
      final parsed = jsonDecode(json);
      if (parsed is List) {
        for (final item in parsed) {
          if (item is Map) {
            final index = item['index'];
            final translation = item['translation']?.toString() ?? '';
            if (index != null && translation.isNotEmpty) {
              final idx = index is int ? index : int.tryParse(index.toString()) ?? -1;
              if (idx >= 0 && idx < blocks.length) {
                result[blocks[idx]['id']] = translation;
              }
            }
          }
        }
      }
    } catch (_) {
      final lines = response.split('\n');
      for (var i = 0; i < lines.length && i < blocks.length; i++) {
        final line = lines[i].replaceAll(RegExp(r'^\[\d+\]\s*'), '').trim();
        if (line.isNotEmpty) {
          result[blocks[i]['id']] = line;
        }
      }
    }
    return result;
  }

  void _updateOverlay(List<Map<String, dynamic>> blocks, FloatingAssistantSettings floating) {
    FloatingAssistantBridge.instance.updateTranslationOverlay({
      'blocks': blocks,
      'style': floating.mangaOverlayStyle,
      'opacity': floating.mangaOverlayOpacity,
      'layoutMode': floating.mangaLayoutMode,
    });
  }

  Future<void> _saveToHistory(List<Map<String, dynamic>> blocks) async {
    if (blocks.isEmpty) return;
    final original = blocks.map((b) => b['originalText']?.toString() ?? '').join(' | ');
    final translated = blocks.map((b) => b['translatedText']?.toString() ?? '').join(' | ');
    final packageName = blocks.first['packageName']?.toString() ?? '';
    _translationHistory.insert(0, {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'originalText': original,
      'translatedText': translated,
      'packageName': packageName,
    });
    if (_translationHistory.length > _maxHistoryEntries) {
      _translationHistory.removeRange(_maxHistoryEntries, _translationHistory.length);
    }
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_translationHistoryKey, jsonEncode(_translationHistory));
    } catch (e) {
      debugPrint('Failed to save translation history: $e');
    }
  }

  Future<void> loadTranslationHistory() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_translationHistoryKey);
      if (raw != null) {
        final list = jsonDecode(raw) as List;
        _translationHistory.clear();
        _translationHistory.addAll(list.cast<Map>().map(Map<String, dynamic>.from));
      }
    } catch (e) {
      debugPrint('Failed to load translation history: $e');
    }
  }

  List<Map<String, dynamic>> get translationHistory =>
      List.unmodifiable(_translationHistory);

  void clearTranslation() {
    if (_translationText.isEmpty && !_translationOverlayActive) return;
    _translationText = '';
    _status = '';
    _translatedCache.clear();
    _translationOverlayActive = false;
    FloatingAssistantBridge.instance.clearTranslationOverlay();
    _onChanged();
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

  Future<void> dispose() async {
    await _subscription?.cancel();
    _api.dispose();
  }

  ModelConfig? _currentModel() {
    final chatModels = _models.modelsByCategory(ModelConfig.categoryChat);
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
      systemPrompt: appSettings.systemPrompt,
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
    final promptContent = conversation.settings.selectedSystemPromptId != null
        ? _settings.effectiveSystemPromptFor(
            conversation.settings.selectedSystemPromptId,
            conversation.settings.systemPrompt,
          )
        : conversation.settings.systemPrompt;
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
    required int depth,
    required String? priorThinking,
  }) {
    final generation = ++_generation;
    final screenContextEnabled = _screenContextToolAllowed;
    final conversationSettings = _conversations
        .getConversation(conversationId)
        ?.settings;
    final stream = _api.sendStreamRequest(
      model,
      working,
      thinking: model.supportsThinking,
      tools: allowTools
          ? ToolCallService.openAITools(
              _plugins.plugins,
              conversationSettings?.agentEnabled == true,
              _settings.settings.agentGrantedPermissions,
              conversationSettings?.imageGenerationEnabled == true,
              screenContextEnabled,
            )
          : const [],
      toolChoice: 'auto',
    );
    var buffer = '';
    var thinkingBuffer = '';
    var finalized = false;

    Future<void> finalize(List<ChatToolCall> toolCalls) async {
      if (finalized || generation != _generation) return;
      finalized = true;
      final thinking = _joinThinking(
        priorThinking,
        thinkingBuffer.isEmpty ? null : thinkingBuffer,
      );
      if (toolCalls.isNotEmpty && allowTools && depth < _maxToolDepth) {
        _status = '正在调用工具...';
        _onChanged();
        final service = ToolCallService(
          _features,
          plugins: _plugins,
          modelConfigs: _models,
          settings: _settings,
          conversations: _conversations,
          conversationId: conversationId,
          allowScreenContextTool: screenContextEnabled,
        );
        final conversation = _conversations.getConversation(conversationId);
        final results = await service.executeAll(
          toolCalls,
          conversation?.messages ?? const [],
        );
        if (generation != _generation) return;
        working.add(_assistantToolCallMessage(buffer, toolCalls));
        for (final result in results) {
          working.add(_toolResultMessage(result));
        }
        _streamTurn(
          model,
          conversationId,
          working,
          createTitle: createTitle,
          allowTools: allowTools,
          depth: depth + 1,
          priorThinking: thinking,
        );
        return;
      }
      final content = buffer.trim().isEmpty ? _emptyAssistantReply : buffer;
      _streaming = false;
      _status = '';
      _draftContent = '';
      _draftThinking = '';
      _conversations.updateLastMessage(
        conversationId,
        content,
        thinkingContent: thinking,
      );
      if (createTitle) {
        unawaited(_maybeCreateConversationTitle(model, conversationId));
      }
      _onChanged();
    }

    unawaited(_subscription?.cancel());
    _subscription = stream.listen(
      (chunk) {
        if (generation != _generation) return;
        if (chunk.content != null) buffer += chunk.content!;
        if (chunk.reasoningContent != null) {
          thinkingBuffer += chunk.reasoningContent!;
        }
        if (chunk.isDone) {
          unawaited(finalize(chunk.toolCalls));
          return;
        }
        _draftContent = buffer;
        _draftThinking = thinkingBuffer;
        _status = buffer.isEmpty ? '正在等待模型...' : '正在生成...';
        _onChanged();
      },
      onError: (Object error) {
        if (generation != _generation) return;
        _streaming = false;
        _draftContent = '';
        _draftThinking = '';
        _setError(error.toString().replaceFirst('Exception: ', ''));
        final conversation = _conversations.getConversation(conversationId);
        if (conversation != null && conversation.messages.isNotEmpty) {
          _conversations.updateLastMessage(
            conversationId,
            buffer.isEmpty ? '请求失败: $error' : '$buffer\n\n---\n请求失败: $error',
          );
        }
      },
      onDone: () {
        if (generation != _generation || !_streaming) return;
        unawaited(finalize(const []));
      },
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
        _onChanged();
      }
    } catch (_) {}
  }

  Map<String, dynamic> _assistantToolCallMessage(
    String content,
    List<ChatToolCall> calls,
  ) {
    return {
      'role': 'assistant',
      'content': content,
      'reasoning_content': '',
      'tool_calls': calls
          .map(
            (call) => {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': const JsonEncoder().convert(call.arguments),
              },
            },
          )
          .toList(growable: false),
    };
  }

  Map<String, dynamic> _toolResultMessage(ToolExecutionResult result) {
    return {
      'role': 'tool',
      'tool_call_id': result.toolCallId,
      'content': const JsonEncoder().convert(
        ToolCallService.modelVisibleToolResult(result.result),
      ),
    };
  }

  bool _supportsNativeTools(ModelConfig model) {
    return model.apiType != 'ollama' &&
        model.apiType != 'anthropic' &&
        model.supportsTools &&
        model.extraParams['disableTools'] != true;
  }

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

  String? _joinThinking(String? first, String? second) {
    final parts = [
      first,
      second,
    ].where((part) => part != null && part.trim().isNotEmpty).toList();
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  void _clearTransientStatus() {
    _error = '';
    _status = '';
  }

  void _setError(String message) {
    _error = message;
    _status = '';
    _onChanged();
  }
}
