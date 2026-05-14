import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/rendering.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';
import 'package:record/record.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:super_clipboard/super_clipboard.dart';
import '../models/conversation.dart';
import '../models/chat_role.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../models/app_settings.dart';
import '../models/system_prompt.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../services/tool_call_service.dart';
import '../widgets/latex_renderer.dart';

class _RetryEntry {
  String userContent;
  List<MessageImage> userImages;
  String? assistantId;
  String? assistantContent;
  String? thinkingContent;
  _RetryEntry(this.userContent, [this.userImages = const []]);
}

class _PendingImage {
  final String path;
  final String name;
  final int size;
  final String mimeType;
  const _PendingImage({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
  });

  bool get isImage => mimeType.startsWith('image/');

  MessageImage toMessageImage() =>
      MessageImage(path: path, name: name, size: size, mimeType: mimeType);
}

/// 文件名安全化，避免用户相册文件名中包含路径分隔符或特殊字符。
String _safeFileName(String name) {
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return safe.isEmpty ? 'image' : safe;
}

class ChatPage extends StatefulWidget {
  final String? conversationId;
  final int roleChangeSerial;
  final VoidCallback? onConversationLoaded;
  final void Function(bool Function() handler)? onBackHandlerChanged;
  final ValueChanged<bool>? onBackAvailabilityChanged;
  const ChatPage({
    super.key,
    this.conversationId,
    this.roleChangeSerial = 0,
    this.onConversationLoaded,
    this.onBackHandlerChanged,
    this.onBackAvailabilityChanged,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  static const _backgroundServiceChannel = MethodChannel(
    'lynai/background_service',
  );
  static const _nativeToolsChannel = MethodChannel('lynai/native_tools');
  static const _emptyAssistantReply = '模型没有返回内容，请稍后重试或检查模型配置。';
  static const _streamWaitTimeout = Duration(minutes: 5);

  final _msgCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  final _focusNode = FocusNode();
  final _screenshotCtrl = ScreenshotController();
  final _audioRecorder = AudioRecorder();
  final _api = ApiService();

  String? _convId;
  String? _pendingModelId;
  bool _thinking = true;
  ConversationSettings? _draftSettings;
  bool _streaming = false;
  bool _showAttach = false;
  bool _showModelMenu = false;
  bool _recording = false;
  bool _transcribingSpeech = false;
  bool _autoScrollToBottom = true;
  bool _showScrollToBottom = false;
  int _scrollGen = 0;
  String? _thinkingTxt;
  bool _thinkExpanded = false;
  final Map<String, String?> _thinkMap = {};
  final Set<String> _expandedThinkIds = {};
  final List<_PendingImage> _pendingImages = [];
  bool _showImageRecognitionList = false;
  bool _shareSelecting = false;
  bool _sharingImage = false;
  final Set<String> _selectedShareMessageIds = {};
  String? _expandedInputAction;
  Timer? _inputActionCollapseTimer;

  int _streamGen = 0;
  String? _streamingConvId;
  DateTime? _lastStreamUiUpdate;
  Timer? _streamWaitTimer;

  final List<_RetryEntry> _retryHistory = [];
  String? _retryMsgId;
  int _retryIdx = 0;

  static const _shareImagePixelRatio = 2.5;
  static const _sharePageMaxWeight = 3600;
  static const _shareMessageChunkLength = 2800;

  late stt.SpeechToText _speech;
  StreamSubscription<StreamChunk>? _sub;
  String? _recordPath;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    if (widget.conversationId != null) {
      _convId = widget.conversationId;
      _applyConversationSettings(widget.conversationId!, notifyNow: false);
      widget.onConversationLoaded?.call();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onBackHandlerChanged?.call(_handleBack);
  }

  bool _handleBack() {
    if (_shareSelecting) {
      _cancelShareSelection();
      return true;
    }
    return false;
  }

  @override
  void didUpdateWidget(ChatPage old) {
    super.didUpdateWidget(old);
    if (widget.conversationId != null && widget.conversationId != _convId) {
      setState(() {
        _convId = widget.conversationId;
        _clearPendingState();
        _clearRetryState();
      });
      _applyConversationSettings(widget.conversationId!, notifyNow: false);
      widget.onConversationLoaded?.call();
    } else if (widget.roleChangeSerial != old.roleChangeSerial) {
      if (_streaming) _stopStreaming();
      setState(() {
        _convId = null;
        _clearPendingState();
        _clearRetryState();
      });
    }
  }

  ConversationSettings _roleSettings(ModelConfig model) {
    final sp = context.read<SettingsProvider>();
    final settings = sp.settings;
    final role = sp.currentRole;
    return ConversationSettings(
      modelId: role.modelId ?? model.id,
      thinking: _thinking,
      selectedSystemPromptId: role.id == ChatRole.defaultId ? null : role.id,
      systemPrompt: role.systemPrompt,
      speechModelId: settings.speechModelId,
      imageModelId: settings.imageModelId,
      imageOcrEnabled: settings.imageOcrEnabled,
      imageRecognitionModelId: settings.imageRecognitionModelId,
      imageRecognitionEnabled: settings.imageRecognitionEnabled,
      imageRecognitionPrompt: settings.imageRecognitionPrompt,
    );
  }

  void _applyConversationSettings(
    String conversationId, {
    bool notifyNow = true,
  }) {
    final conv = context.read<ConversationProvider>().getConversation(
      conversationId,
    );
    if (conv == null) return;
    _draftSettings = null;
    _thinking = conv.settings.thinking;
    final settings = conv.settings;
    void apply() {
      if (!mounted) return;
      context.read<SettingsProvider>().applyConversationSettings(settings);
    }

    if (notifyNow) {
      apply();
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => apply());
    }
  }

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(() => false);
    widget.onBackAvailabilityChanged?.call(false);
    _sub?.cancel();
    _setBackgroundGenerationActive(false);
    _inputActionCollapseTimer?.cancel();
    _streamWaitTimer?.cancel();
    unawaited(_speech.stop());
    _audioRecorder.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _setStreaming(bool value) {
    if (_streaming == value) return;
    if (!value) {
      _streamingConvId = null;
      _lastStreamUiUpdate = null;
    }
    _streaming = value;
    _setBackgroundGenerationActive(value);
  }

  void _beginStreaming(String conversationId) {
    _streamingConvId = conversationId;
    _lastStreamUiUpdate = null;
    _setStreaming(true);
  }

  bool _shouldUpdateStreamUi({bool force = false}) {
    if (force) {
      _lastStreamUiUpdate = DateTime.now();
      return true;
    }
    final now = DateTime.now();
    final last = _lastStreamUiUpdate;
    if (last != null && now.difference(last).inMilliseconds < 80) {
      return false;
    }
    _lastStreamUiUpdate = now;
    return true;
  }

  void _setBackgroundGenerationActive(bool active) {
    unawaited(
      _backgroundServiceChannel
          .invokeMethod<void>(active ? 'startGeneration' : 'stopGeneration')
          .catchError((_) {}),
    );
  }

  void _clearRetryState() {
    _retryHistory.clear();
    _retryMsgId = null;
    _retryIdx = 0;
  }

  void _clearPendingState() {
    _pendingModelId = null;
    _draftSettings = null;
    _thinkingTxt = null;
    _thinkExpanded = false;
    _expandedThinkIds.clear();
    _thinkMap.clear();
    _pendingImages.clear();
  }

  bool get _isNearBottom {
    if (!_scrollCtrl.hasClients) return true;
    final pos = _scrollCtrl.position;
    return pos.maxScrollExtent - pos.pixels <= 48;
  }

  void _syncBottomState() {
    if (!_scrollCtrl.hasClients) return;
    final nearBottom = _isNearBottom;
    if (_autoScrollToBottom == nearBottom &&
        _showScrollToBottom == !nearBottom) {
      return;
    }
    setState(() {
      _autoScrollToBottom = nearBottom;
      _showScrollToBottom = !nearBottom;
    });
  }

  bool _onScrollNotification(ScrollNotification notification) {
    if (notification is ScrollStartNotification &&
        notification.dragDetails != null &&
        _autoScrollToBottom &&
        !_isNearBottom) {
      _pauseAutoScroll();
      return false;
    }
    if (notification is UserScrollNotification &&
        notification.direction == ScrollDirection.forward &&
        _autoScrollToBottom &&
        !_isNearBottom) {
      _pauseAutoScroll();
      return false;
    }
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _syncBottomState();
    }
    return false;
  }

  void _pauseAutoScroll() {
    _scrollGen++;
    setState(() {
      _autoScrollToBottom = false;
      _showScrollToBottom = true;
    });
  }

  void _scrollEnd({bool force = false}) {
    if (!force && !_autoScrollToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        if (!force && !_autoScrollToBottom) return;
        final target = _scrollCtrl.position.maxScrollExtent;
        if (!force) {
          _scrollCtrl.jumpTo(target);
          return;
        }
        final scrollGen = ++_scrollGen;
        _scrollCtrl
            .animateTo(
              target,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              if (!mounted || scrollGen != _scrollGen) return;
              if (_scrollCtrl.hasClients) _syncBottomState();
            });
      }
    });
  }

  void _jumpToBottom() {
    setState(() {
      _autoScrollToBottom = true;
      _showScrollToBottom = false;
    });
    _scrollEnd(force: true);
  }

  void _showMissingChatModelTip() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先在设置中添加 AI 模型')));
  }

  void _stopStreaming() {
    if (!_streaming) return;
    _streamWaitTimer?.cancel();
    _streamWaitTimer = null;
    final cid = _streamingConvId ?? _convId;
    _streamGen++;
    unawaited(_sub?.cancel());
    _sub = null;
    setState(() => _setStreaming(false));
    if (cid == null) return;
    final cp = context.read<ConversationProvider>();
    final conv = cp.getConversation(cid);
    if (conv == null || conv.messages.isEmpty) return;
    final last = conv.messages.last;
    if (last.role == 'assistant' && last.content.trim().isEmpty) {
      cp.updateLastMessage(cid, '已停止生成', save: true);
    } else if (last.role == 'assistant') {
      cp.updateLastMessage(cid, '${last.content}\n\n---\n已停止生成', save: true);
    }
  }

  ModelConfig? _getModel(ModelConfigProvider mp) {
    final chatModels = mp.modelsByCategory(ModelConfig.categoryChat);
    if (chatModels.isEmpty) return null;
    if (_convId != null) {
      final conv = context.read<ConversationProvider>().getConversation(
        _convId!,
      );
      if (conv != null) {
        try {
          return chatModels.firstWhere((m) => m.id == conv.modelId);
        } catch (_) {}
      }
    }
    if (_pendingModelId != null) {
      try {
        return chatModels.firstWhere((m) => m.id == _pendingModelId);
      } catch (_) {}
    }
    final roleModelId = context.read<SettingsProvider>().currentRole.modelId;
    if (_convId == null && roleModelId != null && roleModelId.isNotEmpty) {
      try {
        return chatModels.firstWhere((m) => m.id == roleModelId);
      } catch (_) {}
    }
    final settings = _draftSettings;
    if (settings != null) {
      try {
        return chatModels.firstWhere((m) => m.id == settings.modelId);
      } catch (_) {}
    }
    final lastChatModelId = context
        .read<SettingsProvider>()
        .settings
        .lastChatModelId;
    if (lastChatModelId != null && lastChatModelId.isNotEmpty) {
      try {
        return chatModels.firstWhere((m) => m.id == lastChatModelId);
      } catch (_) {}
    }
    return chatModels.first;
  }

  ConversationSettings _currentConversationSettings(ModelConfig model) {
    if (_convId != null) {
      final conv = context.read<ConversationProvider>().getConversation(
        _convId!,
      );
      if (conv != null) return conv.settings.copyWith(thinking: _thinking);
    }
    if (_draftSettings != null) {
      return _draftSettings!.copyWith(modelId: model.id, thinking: _thinking);
    }
    final role = context.read<SettingsProvider>().currentRole;
    if (role.id != ChatRole.defaultId || role.modelId != null) {
      return _roleSettings(model).copyWith(modelId: role.modelId ?? model.id);
    }
    final set = context.read<SettingsProvider>().settings;
    return ConversationSettings(
      modelId: model.id,
      thinking: _thinking,
      selectedSystemPromptId: set.selectedSystemPromptId,
      systemPrompt: set.systemPrompt,
      speechModelId: set.speechModelId,
      imageModelId: set.imageModelId,
      imageOcrEnabled: set.imageOcrEnabled,
      imageRecognitionModelId: set.imageRecognitionModelId,
      imageRecognitionEnabled: set.imageRecognitionEnabled,
      imageRecognitionPrompt: set.imageRecognitionPrompt,
    );
  }

  void _saveDraftSettings(ConversationSettings settings) {
    _draftSettings = settings;
    context.read<SettingsProvider>().applyConversationSettings(settings);
  }

  void _saveConversationSettings(ConversationSettings settings) {
    if (_convId != null) {
      context.read<ConversationProvider>().updateConversationSettings(
        _convId!,
        settings,
      );
    } else {
      _saveDraftSettings(settings);
      return;
    }
    context.read<SettingsProvider>().applyConversationSettings(settings);
  }

  ConversationSettings? _activeSettings() {
    if (_convId != null) {
      final conv = context.read<ConversationProvider>().getConversation(
        _convId!,
      );
      if (conv != null) return conv.settings.copyWith(thinking: _thinking);
    }
    return _draftSettings;
  }

  ConversationSettings _imageRecognitionSettings() {
    return _activeSettings() ?? _settingsToConversationSettings();
  }

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if ((text.isEmpty && _pendingImages.isEmpty) || _streaming) return;
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    if (mp.modelsByCategory(ModelConfig.categoryChat).isEmpty) {
      _showMissingChatModelTip();
      return;
    }
    final model = _getModel(mp);
    if (model == null) {
      _showMissingChatModelTip();
      return;
    }
    final images = _pendingImages.map((e) => e.toMessageImage()).toList();
    final conversationSettings = _currentConversationSettings(model);
    final roleId = context.read<SettingsProvider>().settings.currentRoleId;
    final apiUserContent = await _prepareUserContent(text, images);
    if (!mounted) return;
    if (apiUserContent == null) {
      _setBackgroundGenerationActive(false);
      return;
    }

    _convId ??= cp.createConversation(conversationSettings, roleId: roleId);
    _pendingModelId = null;
    _clearRetryState();
    final isFirstUserMessage =
        _convId != null &&
        (cp.getConversation(_convId!)?.messages.isEmpty ?? false);
    cp.addMessage(_convId!, 'user', text, images: images);
    _msgCtrl.clear();
    setState(() {
      _pendingImages.clear();
      _beginStreaming(_convId!);
      _thinkingTxt = null;
    });
    _scrollEnd(force: true);
    cp.addMessage(_convId!, 'assistant', '');
    _doSend(
      model,
      lastUserContentOverride: apiUserContent,
      createTitle: isFirstUserMessage,
    );
  }

  void _doSend(
    ModelConfig model, {
    Object? lastUserContentOverride,
    bool createTitle = false,
  }) {
    final cid = _convId;
    if (cid == null) return;
    final conv = context.read<ConversationProvider>().getConversation(cid);
    if (conv == null) return;
    final msgs = _buildApiMessages(
      conv,
      lastUserContentOverride: lastUserContentOverride,
      enableTools: _supportsNativeTools(model),
    );
    _doStream(model, cid, msgs, createTitle: createTitle);
  }

  Future<void> _sendRetry(String text) async {
    if (_streaming || _convId == null) return;
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    final model = _getModel(mp);
    if (model == null) return;
    final conv = cp.getConversation(_convId!);
    if (conv == null) return;
    final lastUser = conv.messages.where((m) => m.role == 'user').last;
    Object? apiUserContent;
    try {
      apiUserContent = await _prepareUserContent(text, lastUser.images);
      if (!mounted || apiUserContent == null) return;
    } catch (_) {
      return;
    }
    _retryMsgId = lastUser.id;

    final lastAssistant = conv.messages
        .where((m) => m.role == 'assistant')
        .toList();
    if (lastAssistant.isNotEmpty && lastAssistant.last.content.isNotEmpty) {
      _saveRetryHistoryEntry(
        lastUser.content,
        lastUser.images,
        lastAssistant.last.id,
        lastAssistant.last.content,
      );
    }

    _retryHistory.add(_RetryEntry(text, lastUser.images));
    _retryIdx = _retryHistory.length - 1;
    cp.updateMessageContent(_convId!, lastUser.id, text);
    if (lastAssistant.isNotEmpty) {
      _thinkMap.remove(lastAssistant.last.id);
      cp.deleteMessage(_convId!, lastAssistant.last.id);
    }
    _scrollEnd(force: true);
    cp.addMessage(_convId!, 'assistant', '');
    setState(() {
      _beginStreaming(_convId!);
      _thinkingTxt = null;
    });
    _doSend(model, lastUserContentOverride: apiUserContent);
  }

  List<Map<String, dynamic>> _buildApiMessages(
    Conversation conv, {
    Object? lastUserContentOverride,
    bool enableTools = false,
  }) {
    final msgs = <Map<String, dynamic>>[];
    final promptContent = conv.settings.selectedSystemPromptId != null
        ? context.read<SettingsProvider>().effectiveSystemPromptFor(
            conv.settings.selectedSystemPromptId,
            conv.settings.systemPrompt,
          )
        : conv.settings.systemPrompt;
    if (promptContent.isNotEmpty) {
      msgs.add({
        'role': 'system',
        'content': enableTools
            ? '$promptContent\n\n${ToolCallService.nativeSystemPrompt}\n\n${ToolCallService.currentTimeContext()}'
            : promptContent,
      });
    } else if (enableTools) {
      msgs.add({
        'role': 'system',
        'content':
            '${ToolCallService.nativeSystemPrompt}\n\n${ToolCallService.currentTimeContext()}',
      });
    }
    final lastUserIndex = lastUserContentOverride == null
        ? -1
        : conv.messages.lastIndexWhere((m) => m.role == 'user');
    for (var i = 0; i < conv.messages.length; i++) {
      final m = conv.messages[i];
      if (m.role == 'assistant' && m.content.isEmpty) continue;
      msgs.add({
        'role': m.role,
        'content': i == lastUserIndex ? lastUserContentOverride : m.content,
        if (m.role == 'assistant' &&
            m.thinkingContent != null &&
            m.thinkingContent!.isNotEmpty)
          'reasoning_content': m.thinkingContent,
      });
    }
    return msgs;
  }

  bool _supportsNativeTools(ModelConfig model) {
    return model.apiType != 'ollama' &&
        model.apiType != 'anthropic' &&
        model.supportsTools &&
        model.extraParams['disableTools'] != true;
  }

  bool _supportsThinking(ModelConfig model) => model.supportsThinking;

  bool _supportsVision(ModelConfig model) => model.supportsVision;

  Map<String, dynamic> _assistantToolCallMessage(
    String content,
    List<ChatToolCall> calls,
  ) {
    return {
      'role': 'assistant',
      'content': content,
      'tool_calls': calls
          .map(
            (call) => {
              'id': call.id,
              'type': 'function',
              'function': {
                'name': call.name,
                'arguments': _jsonEncode(call.arguments),
              },
            },
          )
          .toList(),
    };
  }

  Map<String, dynamic> _toolResultMessage(
    ToolExecutionResult result, {
    required bool nativeTool,
  }) {
    final content = _jsonEncode(result.result);
    if (nativeTool) {
      return {
        'role': 'tool',
        'tool_call_id': result.toolCallId,
        'name': result.name,
        'content': content,
      };
    }
    return {
      'role': 'user',
      'content': '工具 ${result.name} 返回：$content\n请根据工具结果给用户最终回复。',
    };
  }

  String _jsonEncode(Object? value) => const JsonEncoder().convert(value);

  Future<void> _maybeCreateConversationTitle(
    ModelConfig model,
    String cid,
  ) async {
    final cp = context.read<ConversationProvider>();
    final conv = cp.getConversation(cid);
    if (conv == null ||
        conv.messages.where((m) => m.role == 'user').length != 1) {
      return;
    }
    final firstUser = conv.messages.firstWhere((m) => m.role == 'user');
    try {
      final response = await _api.sendChatRequest(model, [
        {
          'role': 'system',
          'content': '根据用户第一条消息创建一个简短中文对话标题，只返回标题本身，最多 16 个字。',
        },
        {'role': 'user', 'content': firstUser.content},
      ], thinking: false);
      if (!mounted) return;
      final title = response.content
          .replaceAll(RegExp(r'[\r\n"“”]'), '')
          .trim();
      if (title.isNotEmpty) {
        cp.updateConversationTitle(
          cid,
          title.length > 24 ? title.substring(0, 24) : title,
        );
      }
    } catch (_) {}
  }

  void _doStream(
    ModelConfig model,
    String cid,
    List<Map<String, dynamic>> msgs, {
    bool createTitle = false,
  }) {
    _doStreamTurn(
      model,
      cid,
      List<Map<String, dynamic>>.from(msgs),
      createTitle: createTitle,
      allowTools: _supportsNativeTools(model),
      depth: 0,
      priorThink: null,
    );
  }

  void _doStreamTurn(
    ModelConfig model,
    String cid,
    List<Map<String, dynamic>> working, {
    required bool createTitle,
    required bool allowTools,
    required int depth,
    required String? priorThink,
  }) {
    if (!mounted) return;
    final cp = context.read<ConversationProvider>();
    final gen = ++_streamGen;
    final stream = _api.sendStreamRequest(
      model,
      working,
      thinking: _thinking && _supportsThinking(model),
      tools: allowTools ? ToolCallService.openAITools() : const [],
      toolChoice: depth >= 3 ? 'none' : 'auto',
    );
    String buf = '', thinkBuf = '';
    var finalized = false;
    var timeoutDisplayed = false;
    void armWaitTimeout() {
      _streamWaitTimer?.cancel();
      _streamWaitTimer = Timer(_streamWaitTimeout, () {
        if (!mounted || gen != _streamGen || finalized || !_streaming) return;
        timeoutDisplayed = true;
        cp.updateLastMessage(cid, '请求等待已超过 5 分钟，仍在继续接收模型返回。', save: true);
      });
    }

    void clearWaitTimeout() {
      _streamWaitTimer?.cancel();
      _streamWaitTimer = null;
    }

    Future<void> finalizeStream(List<ChatToolCall> toolCalls) async {
      if (finalized) return;
      finalized = true;
      clearWaitTimeout();
      final currentThink = thinkBuf.isNotEmpty ? thinkBuf : null;
      final think = _joinThinking(priorThink, currentThink);
      if (toolCalls.isNotEmpty && allowTools && depth < 4) {
        final toolService = ToolCallService(context.read<FeatureProvider>());
        final conv = cp.getConversation(cid);
        final results = await toolService.executeAll(
          toolCalls,
          conv?.messages ?? const [],
        );
        if (!mounted || gen != _streamGen) return;
        working.add(_assistantToolCallMessage(buf, toolCalls));
        for (final result in results) {
          working.add(_toolResultMessage(result, nativeTool: true));
        }
        if (think != null) {
          setState(() => _thinkingTxt = think);
        }
        _doStreamTurn(
          model,
          cid,
          working,
          createTitle: createTitle,
          allowTools: allowTools,
          depth: depth + 1,
          priorThink: think,
        );
        return;
      }
      final content = buf.trim().isEmpty ? _emptyAssistantReply : buf;
      _shouldUpdateStreamUi(force: true);
      setState(() {
        _setStreaming(false);
        _thinkingTxt = think;
      });
      cp.updateLastMessage(cid, content, thinkingContent: think, save: true);
      final conv = cp.getConversation(cid);
      if (conv != null && conv.messages.isNotEmpty) {
        final lastMsg = conv.messages.last;
        if (think != null) _thinkMap[lastMsg.id] = think;
        if (_retryHistory.isNotEmpty && _retryIdx < _retryHistory.length) {
          _retryHistory[_retryIdx].assistantId = lastMsg.id;
          _retryHistory[_retryIdx].assistantContent = content;
          _retryHistory[_retryIdx].thinkingContent = think;
        }
      }
      if (createTitle) unawaited(_maybeCreateConversationTitle(model, cid));
      _scrollEnd();
    }

    _sub?.cancel();
    armWaitTimeout();
    _sub = stream.listen(
      (chunk) {
        if (!mounted || gen != _streamGen) return;
        armWaitTimeout();
        if (chunk.content != null) buf += chunk.content!;
        if (chunk.reasoningContent != null) thinkBuf += chunk.reasoningContent!;
        if (chunk.isDone) {
          unawaited(finalizeStream(chunk.toolCalls));
        } else {
          if (timeoutDisplayed && (buf.isNotEmpty || thinkBuf.isNotEmpty)) {
            timeoutDisplayed = false;
            cp.updateLastMessage(cid, buf, save: false);
            if (thinkBuf.isNotEmpty) setState(() => _thinkingTxt = thinkBuf);
            _scrollEnd();
          } else if (_shouldUpdateStreamUi()) {
            cp.updateLastMessage(cid, buf, save: false);
            if (thinkBuf.isNotEmpty) setState(() => _thinkingTxt = thinkBuf);
            _scrollEnd();
          }
        }
      },
      onError: (e) {
        if (!mounted || gen != _streamGen) return;
        clearWaitTimeout();
        setState(() => _setStreaming(false));
        String msg = e.toString();
        if (msg.startsWith('Exception: ')) msg = msg.substring(11);
        final display = buf.isNotEmpty
            ? '$buf\n\n---\n请求失败: $msg'
            : '请求失败: $msg';
        cp.updateLastMessage(cid, display, save: true);
      },
      onDone: () {
        if (!mounted || gen != _streamGen) return;
        clearWaitTimeout();
        if (_streaming) {
          unawaited(finalizeStream(const []));
        } else {
          setState(() => _setStreaming(false));
        }
      },
    );
  }

  String? _joinThinking(String? first, String? second) {
    final parts = [first, second]
        .where((part) => part != null && part.trim().isNotEmpty)
        .map((part) => part!.trim())
        .toList();
    if (parts.isEmpty) return null;
    return parts.join('\n\n');
  }

  void _switchModel(ModelConfig model) {
    if (_convId != null) {
      context.read<ConversationProvider>().updateConversationModelId(
        _convId!,
        model.id,
      );
    } else {
      _pendingModelId = model.id;
      _draftSettings = _currentConversationSettings(
        model,
      ).copyWith(modelId: model.id);
    }
    context.read<SettingsProvider>().setLastChatModelId(model.id);
    setState(() {});
  }

  void _setSubModel(ModelConfig config, String modelName) {
    final mp = context.read<ModelConfigProvider>();
    final updated = config.copyWith(modelName: modelName);
    mp.updateModel(updated);
    _switchModel(updated);
    setState(() => _showModelMenu = false);
  }

  Future<void> _retry() async {
    if (_convId == null || _streaming) return;
    final cp = context.read<ConversationProvider>();
    final conv = cp.getConversation(_convId!);
    if (conv == null) return;
    final um = conv.messages.where((m) => m.role == 'user').toList();
    if (um.isEmpty) return;
    final assistantMessages = conv.messages
        .where((m) => m.role == 'assistant')
        .toList();
    if (assistantMessages.isEmpty) return;
    final lastUser = um.last;
    Object? apiUserContent;
    try {
      apiUserContent = await _prepareUserContent(
        lastUser.content,
        lastUser.images,
      );
      if (!mounted || apiUserContent == null) return;
    } catch (_) {
      return;
    }
    _retryMsgId = lastUser.id;

    final lastAssistant = assistantMessages.last;
    if (lastAssistant.content.isNotEmpty) {
      _saveRetryHistoryEntry(
        lastUser.content,
        lastUser.images,
        lastAssistant.id,
        lastAssistant.content,
      );
    }

    _retryHistory.add(_RetryEntry(lastUser.content, lastUser.images));
    _retryIdx = _retryHistory.length - 1;
    _thinkMap.remove(lastAssistant.id);
    cp.deleteMessage(_convId!, lastAssistant.id);
    cp.addMessage(_convId!, 'assistant', '');
    setState(() {
      _beginStreaming(_convId!);
      _thinkingTxt = null;
    });
    final retryModel = _getModel(context.read<ModelConfigProvider>());
    if (retryModel != null) {
      _doSend(retryModel, lastUserContentOverride: apiUserContent);
    } else {
      setState(() => _setStreaming(false));
      _showMissingChatModelTip();
    }
  }

  Future<void> _retryWithoutHistory() async {
    if (_convId == null || _streaming) return;
    final cp = context.read<ConversationProvider>();
    final conv = cp.getConversation(_convId!);
    if (conv == null) return;
    final assistantMessages = conv.messages
        .where((m) => m.role == 'assistant')
        .toList();
    if (assistantMessages.isEmpty) return;
    final lastAssistant = assistantMessages.last;
    final retryModel = _getModel(context.read<ModelConfigProvider>());
    if (retryModel != null) {
      final conv = cp.getConversation(_convId!);
      final userMessages = conv?.messages
          .where((m) => m.role == 'user')
          .toList();
      final lastUser = userMessages == null || userMessages.isEmpty
          ? null
          : userMessages.last;
      Object? apiUserContent;
      if (lastUser != null) {
        try {
          apiUserContent = await _prepareUserContent(
            lastUser.content,
            lastUser.images,
          );
          if (!mounted) return;
          if (apiUserContent == null) return;
        } catch (e) {
          if (!mounted) return;
          return;
        }
      }
      _thinkMap.remove(lastAssistant.id);
      cp.deleteMessage(_convId!, lastAssistant.id);
      cp.addMessage(_convId!, 'assistant', '');
      setState(() {
        _beginStreaming(_convId!);
        _thinkingTxt = null;
      });
      _doSend(retryModel, lastUserContentOverride: apiUserContent);
    } else {
      setState(() => _setStreaming(false));
      _showMissingChatModelTip();
    }
  }

  void _saveRetryHistoryEntry(
    String userContent,
    List<MessageImage> userImages,
    String assistantId,
    String assistantContent,
  ) {
    if (_retryHistory.isEmpty) {
      final oldEntry = _RetryEntry(userContent, userImages);
      oldEntry.assistantId = assistantId;
      oldEntry.assistantContent = assistantContent;
      oldEntry.thinkingContent = _thinkingTxt ?? _thinkMap[assistantId];
      _retryHistory.add(oldEntry);
    } else if (_retryIdx < _retryHistory.length) {
      _retryHistory[_retryIdx].userImages = userImages;
      _retryHistory[_retryIdx].assistantId = assistantId;
      _retryHistory[_retryIdx].assistantContent = assistantContent;
      _retryHistory[_retryIdx].thinkingContent =
          _thinkingTxt ?? _thinkMap[assistantId];
    }
  }

  void _copy(String c) {
    Clipboard.setData(ClipboardData(text: c));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('已复制'), duration: Duration(seconds: 1)),
      );
    }
  }

  void _startShareSelection([Message? initialMessage]) {
    final conv = _convId == null
        ? null
        : context.read<ConversationProvider>().getConversation(_convId!);
    if (conv == null || conv.messages.isEmpty) return;
    setState(() {
      _shareSelecting = true;
      _selectedShareMessageIds.clear();
      if (initialMessage != null) {
        _selectedShareMessageIds.add(initialMessage.id);
      }
    });
    widget.onBackAvailabilityChanged?.call(true);
  }

  void _cancelShareSelection() {
    if (!_shareSelecting) return;
    setState(() {
      _shareSelecting = false;
      _selectedShareMessageIds.clear();
    });
    widget.onBackAvailabilityChanged?.call(false);
  }

  void _toggleShareMessage(Message msg) {
    setState(() {
      if (_selectedShareMessageIds.contains(msg.id)) {
        _selectedShareMessageIds.remove(msg.id);
      } else {
        _selectedShareMessageIds.add(msg.id);
      }
    });
  }

  Future<void> _shareSelectedMessages() async {
    if (_sharingImage || _convId == null || _selectedShareMessageIds.isEmpty) {
      return;
    }
    try {
      setState(() => _sharingImage = true);
      final images = await _captureShareImages();
      if (images.isEmpty) return;
      if (mounted) {
        if (_isDesktopPlatform) {
          final clipboard = SystemClipboard.instance;
          if (clipboard == null) {
            throw Exception('当前平台不支持写入剪贴板');
          }
          final items = <DataWriterItem>[];
          for (var i = 0; i < images.length; i++) {
            final suffix = images.length == 1 ? '' : ' ${i + 1}';
            final item = DataWriterItem(suggestedName: 'LynAI 对话$suffix.png');
            item.add(Formats.png(images[i]));
            items.add(item);
          }
          await clipboard.write(items);
          if (mounted) {
            _showShareImageSnack(
              _shareImageDoneText('长图已复制到剪贴板', images.length),
            );
          }
        } else {
          final files = <XFile>[];
          final timestamp = DateTime.now().millisecondsSinceEpoch;
          for (var i = 0; i < images.length; i++) {
            final f = File(
              '${Directory.systemTemp.path}/${_shareImageFileName(timestamp, i, images.length)}',
            );
            await f.writeAsBytes(images[i]);
            files.add(XFile(f.path));
          }
          await SharePlus.instance.share(
            ShareParams(files: files, text: 'LynAI 对话'),
          );
        }
        _cancelShareSelection();
      }
    } catch (e) {
      if (mounted) {
        _showShareImageSnack('分享失败: $e');
      }
    } finally {
      if (mounted) setState(() => _sharingImage = false);
    }
  }

  Future<void> _saveSelectedMessagesImage() async {
    if (_sharingImage || _convId == null || _selectedShareMessageIds.isEmpty) {
      return;
    }
    try {
      setState(() => _sharingImage = true);
      final images = await _captureShareImages();
      if (images.isEmpty) return;
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      if (Platform.isAndroid) {
        for (var i = 0; i < images.length; i++) {
          final result = await _nativeToolsChannel
              .invokeMapMethod<String, dynamic>('saveImageToGallery', {
                'bytes': images[i],
                'fileName': _shareImageFileName(timestamp, i, images.length),
              });
          if (result?['ok'] != true) {
            throw Exception(result?['error'] ?? '保存到图库失败');
          }
        }
        if (!mounted) return;
        _showShareImageSnack(
          _shareImageDoneText('长图已保存到 Pictures/LynAI', images.length),
        );
        return;
      }
      Directory? dir;
      if (_isDesktopPlatform) {
        dir = await getDownloadsDirectory();
      } else {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();
      final files = <File>[];
      for (var i = 0; i < images.length; i++) {
        final file = File(
          '${dir.path}/${_shareImageFileName(timestamp, i, images.length)}',
        );
        await file.writeAsBytes(images[i], flush: true);
        files.add(file);
      }
      if (!mounted) return;
      _showShareImageSnack(_savedShareImagePathText(files));
    } catch (e) {
      if (!mounted) return;
      _showShareImageSnack('保存失败: $e');
    } finally {
      if (mounted) setState(() => _sharingImage = false);
    }
  }

  Future<List<Uint8List>> _captureShareImages() async {
    if (_convId == null) return const [];
    final conv = context.read<ConversationProvider>().getConversation(_convId!);
    if (conv == null) return const [];
    final selected = conv.messages
        .where((m) => _selectedShareMessageIds.contains(m.id))
        .toList(growable: false);
    if (selected.isEmpty) return const [];
    final settings = context.read<SettingsProvider>().settings;
    final brightness = Theme.of(context).brightness;
    final pages = _shareMessagePages(selected);
    final images = <Uint8List>[];
    for (var i = 0; i < pages.length; i++) {
      final shareWidget = _ShareConversationImage(
        title: conv.title,
        messages: pages[i],
        seedColor: settings.themeColor,
        brightness: brightness,
        pageNumber: pages.length == 1 ? null : i + 1,
        pageCount: pages.length == 1 ? null : pages.length,
      );
      images.add(await _captureSharePageImage(shareWidget));
    }
    return images;
  }

  Future<Uint8List> _captureSharePageImage(Widget shareWidget) async {
    try {
      return await _screenshotCtrl.captureFromLongWidget(
        shareWidget,
        pixelRatio: _shareImagePixelRatio,
        context: context,
        constraints: const BoxConstraints(maxWidth: 720),
      );
    } catch (_) {
      return _screenshotCtrl.captureFromWidget(
        shareWidget,
        pixelRatio: _shareImagePixelRatio,
        context: context,
      );
    }
  }

  List<List<Message>> _shareMessagePages(List<Message> messages) {
    final pages = <List<Message>>[];
    var current = <Message>[];
    var currentWeight = 0;
    for (final message in messages.expand(_splitShareMessage)) {
      final weight = _shareMessageWeight(message);
      if (current.isNotEmpty && currentWeight + weight > _sharePageMaxWeight) {
        pages.add(current);
        current = <Message>[];
        currentWeight = 0;
      }
      current.add(message);
      currentWeight += weight;
    }
    if (current.isNotEmpty) pages.add(current);
    return pages;
  }

  Iterable<Message> _splitShareMessage(Message message) sync* {
    final content = message.content.trim();
    if (content.length <= _shareMessageChunkLength) {
      yield message;
      return;
    }

    final chunks = _splitTextForShare(content);
    for (var i = 0; i < chunks.length; i++) {
      yield Message(
        id: '${message.id}_share_$i',
        role: message.role,
        content: chunks[i],
        images: i == 0 ? message.images : const [],
        thinkingContent: i == 0 ? message.thinkingContent : null,
        timestamp: message.timestamp,
      );
    }
  }

  List<String> _splitTextForShare(String text) {
    final chunks = <String>[];
    var start = 0;
    while (start < text.length) {
      var end = (start + _shareMessageChunkLength).clamp(0, text.length);
      if (end < text.length) {
        final paragraphBreak = text.lastIndexOf('\n\n', end);
        final lineBreak = text.lastIndexOf('\n', end);
        final space = text.lastIndexOf(' ', end);
        final splitAt = [paragraphBreak, lineBreak, space]
            .where((i) => i > start + (_shareMessageChunkLength ~/ 2))
            .fold<int>(-1, (best, i) => i > best ? i : best);
        if (splitAt != -1) end = splitAt;
      }
      final chunk = text.substring(start, end).trim();
      if (chunk.isNotEmpty) chunks.add(chunk);
      start = end;
    }
    return chunks;
  }

  int _shareMessageWeight(Message message) {
    return message.content.length + message.images.length * 800 + 300;
  }

  String _shareImageFileName(int timestamp, int index, int total) {
    final suffix = total == 1 ? '' : '_part_${index + 1}_of_$total';
    return 'lynai_share_$timestamp$suffix.png';
  }

  String _shareImageDoneText(String base, int count) {
    return count == 1 ? base : '$base，共 $count 张';
  }

  String _savedShareImagePathText(List<File> files) {
    if (files.length == 1) return '长图已保存到 ${files.single.path}';
    return '长图已拆分为 ${files.length} 张，保存到 ${files.first.parent.path}';
  }

  void _showShareImageSnack(String message) {
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: messenger.hideCurrentSnackBar,
          child: Text(message),
        ),
        duration: const Duration(seconds: 2),
        showCloseIcon: true,
      ),
    );
  }

  bool get _isDesktopPlatform {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  Future<void> _pickImg() async {
    if (_streaming) return;
    List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage();
      if (picked.isEmpty) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法读取图片，请检查相册权限: $e')));
      return;
    }
    if (!mounted) return;
    final images = <_PendingImage>[];
    try {
      final dir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${dir.path}/message_images');
      if (!await imageDir.exists()) await imageDir.create(recursive: true);
      for (var i = 0; i < picked.length; i++) {
        final item = picked[i];
        final source = File(item.path);
        final storedFile = await source.copy(
          '${imageDir.path}/${DateTime.now().microsecondsSinceEpoch}_${i}_${_safeFileName(item.name)}',
        );
        images.add(
          _PendingImage(
            path: storedFile.path,
            name: item.name,
            size: await storedFile.length(),
            mimeType: item.mimeType ?? _mimeTypeForPath(item.path),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('图片读取失败: $e')));
      return;
    }
    setState(() {
      _pendingImages.addAll(images);
    });
  }

  Future<void> _pickFiles() async {
    if (_streaming) return;
    try {
      final result = await FilePicker.platform.pickFiles(
        allowMultiple: true,
        withData: false,
      );
      if (!mounted || result == null || result.files.isEmpty) return;
      final files = <_PendingImage>[];
      for (final item in result.files) {
        if (item.path == null) continue;
        files.add(await _storeAttachmentFile(File(item.path!), item.name));
      }
      if (files.isEmpty) return;
      setState(() => _pendingImages.addAll(files));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('文件读取失败: $e')));
    }
  }

  Future<void> _takePhoto() async {
    if (_streaming || _isDesktopPlatform) return;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera);
      if (!mounted || picked == null) return;
      final file = await _storeAttachmentFile(
        File(picked.path),
        picked.name,
        mimeType: picked.mimeType ?? _mimeTypeForPath(picked.path),
      );
      setState(() => _pendingImages.add(file));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('拍照失败，请检查相机权限: $e')));
    }
  }

  Future<_PendingImage> _storeAttachmentFile(
    File source,
    String name, {
    String? mimeType,
  }) async {
    final dir = await getApplicationDocumentsDirectory();
    final attachmentDir = Directory('${dir.path}/message_attachments');
    if (!await attachmentDir.exists()) {
      await attachmentDir.create(recursive: true);
    }
    final storedFile = await source.copy(
      '${attachmentDir.path}/${DateTime.now().microsecondsSinceEpoch}_${_safeFileName(name)}',
    );
    return _PendingImage(
      path: storedFile.path,
      name: name,
      size: await storedFile.length(),
      mimeType: mimeType ?? _mimeTypeForPath(name, fallbackPath: source.path),
    );
  }

  Future<void> _handlePasteShortcut() async {
    if (_streaming) return;
    final pastedImage = await _pasteClipboardImage();
    if (pastedImage) return;

    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return;
    try {
      final reader = await clipboard.read();
      if (!reader.canProvide(Formats.plainText)) return;
      final text = await reader.readValue(Formats.plainText);
      if (!mounted || text == null || text.isEmpty) return;

      final value = _msgCtrl.value;
      final selection = value.selection;
      final start = selection.start >= 0 ? selection.start : value.text.length;
      final end = selection.end >= 0 ? selection.end : value.text.length;
      final newText = value.text.replaceRange(start, end, text);
      _msgCtrl.value = value.copyWith(
        text: newText,
        selection: TextSelection.collapsed(offset: start + text.length),
        composing: TextRange.empty,
      );
      setState(() {});
    } catch (_) {}
  }

  Future<bool> _pasteClipboardImage() async {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) return false;
    try {
      final reader = await clipboard.read();
      final fileFormat = reader.canProvide(Formats.png)
          ? Formats.png
          : reader.canProvide(Formats.jpeg)
          ? Formats.jpeg
          : reader.canProvide(Formats.webp)
          ? Formats.webp
          : reader.canProvide(Formats.gif)
          ? Formats.gif
          : null;
      if (fileFormat == null) return false;

      bool pasted = false;
      final completer = Completer<void>();
      final progress = reader.getFile(fileFormat, (file) async {
        final bytes = await file.readAll();
        final ext = _clipboardImageExtension(file.fileName, fileFormat);
        final name = _clipboardImageName(file.fileName, ext);
        await _addClipboardImage(bytes, name);
        pasted = true;
        if (!completer.isCompleted) completer.complete();
      });
      if (progress != null) {
        await completer.future.timeout(const Duration(seconds: 2));
      }
      return pasted;
    } catch (_) {
      return false;
    }
  }

  String _clipboardImageExtension(String? fileName, FileFormat format) {
    final lower = (fileName ?? '').toLowerCase();
    if (lower.endsWith('.png')) return '.png';
    if (lower.endsWith('.jpg') || lower.endsWith('.jpeg')) return '.jpg';
    if (lower.endsWith('.webp')) return '.webp';
    if (lower.endsWith('.gif')) return '.gif';
    if (format == Formats.jpeg) return '.jpg';
    if (format == Formats.webp) return '.webp';
    if (format == Formats.gif) return '.gif';
    return '.png';
  }

  String _clipboardImageName(String? fileName, String ext) {
    final base = (fileName == null || fileName.trim().isEmpty)
        ? 'clipboard_${DateTime.now().millisecondsSinceEpoch}'
        : fileName;
    if (base.toLowerCase().endsWith(ext)) return base;
    return '$base$ext';
  }

  Future<void> _addClipboardImage(Uint8List bytes, String fileName) async {
    if (!mounted) return;
    try {
      final dir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${dir.path}/message_images');
      if (!await imageDir.exists()) await imageDir.create(recursive: true);
      final storedFile = File(
        '${imageDir.path}/${DateTime.now().millisecondsSinceEpoch}_${_safeFileName(fileName)}',
      );
      await storedFile.writeAsBytes(bytes, flush: true);
      final size = bytes.length;
      setState(() {
        _pendingImages.add(
          _PendingImage(
            path: storedFile.path,
            name: fileName,
            size: size,
            mimeType: _mimeTypeForPath(fileName),
          ),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('粘贴图片失败: $e')));
    }
  }

  Future<Object?> _prepareUserContent(
    String text,
    List<MessageImage> files,
  ) async {
    try {
      return await _buildUserContentWithFiles(text, files);
    } catch (e) {
      if (!mounted) return null;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('文件处理失败: $e')));
      return null;
    }
  }

  Future<Object> _buildUserContentWithFiles(
    String text,
    List<MessageImage> files,
  ) async {
    final set = _imageRecognitionSettings();
    final imageFiles = files.where((file) => file.isImage).toList();
    final otherFiles = files.where((file) => !file.isImage).toList();
    final recognized = <String>[];
    final directFiles = <MessageImage>[
      if (!set.imageOcrEnabled) ...imageFiles,
      if (!set.imageRecognitionEnabled) ...otherFiles,
    ];

    if (set.imageOcrEnabled && imageFiles.isNotEmpty) {
      recognized.add(await _recognizeImagesWithOcr(imageFiles, set));
    }
    if (set.imageRecognitionEnabled && otherFiles.isNotEmpty) {
      recognized.add(await _recognizeFilesWithModel(otherFiles, set));
    }

    final buffer = StringBuffer(text.trim());
    if (files.isEmpty) return buffer.toString();
    if (buffer.isNotEmpty) buffer.writeln('\n');
    for (final file in files) {
      buffer.writeln(
        '[文件: ${file.name} (${_fmtSz(file.size)}, ${file.mimeType})]',
      );
    }
    final recognizedText = recognized
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .join('\n');
    if (recognizedText.isNotEmpty) {
      buffer.writeln(recognizedText);
    }

    return _directModelContent(buffer.toString().trim(), directFiles);
  }

  ConversationSettings _settingsToConversationSettings() {
    final settings = context.read<SettingsProvider>().settings;
    final model = _getModel(context.read<ModelConfigProvider>());
    return ConversationSettings(
      modelId: model?.id ?? settings.lastChatModelId ?? '',
      thinking: _thinking,
      selectedSystemPromptId: settings.selectedSystemPromptId,
      systemPrompt: settings.systemPrompt,
      speechModelId: settings.speechModelId,
      imageModelId: settings.imageModelId,
      imageOcrEnabled: settings.imageOcrEnabled,
      imageRecognitionModelId: settings.imageRecognitionModelId,
      imageRecognitionEnabled: settings.imageRecognitionEnabled,
      imageRecognitionPrompt: settings.imageRecognitionPrompt,
    );
  }

  Future<String> _recognizeFilesWithModel(
    List<MessageImage> files,
    ConversationSettings set,
  ) async {
    if (files.isEmpty) return '';
    final modelId = set.imageRecognitionModelId;
    if (modelId == null || modelId.isEmpty) {
      throw Exception('请先选择文件识别模型');
    }
    final mp = context.read<ModelConfigProvider>();
    final model = _findModelConfigById(
      mp.modelsByCategory(ModelConfig.categoryChat),
      modelId,
    );
    if (model == null) {
      throw Exception('文件识别模型已不存在，请在设置中重新选择');
    }
    if (!_supportsVision(model)) {
      throw Exception('当前文件识别模型未开启视觉能力，请在模型设置中启用');
    }
    final inputs = <ChatFileInput>[];
    for (final file in files) {
      final bytes = await File(file.path).readAsBytes();
      inputs.add(
        ChatFileInput(bytes: bytes, mimeType: file.mimeType, name: file.name),
      );
    }
    return _api.recognizeImageTextWithChatModel(
      model,
      set.imageRecognitionPrompt,
      inputs,
    );
  }

  Future<String> _recognizeImagesWithOcr(
    List<MessageImage> files,
    ConversationSettings set,
  ) async {
    final modelId = set.imageModelId;
    if (modelId == null || modelId.isEmpty) {
      throw Exception('请先选择 OCR 模型');
    }
    final mp = context.read<ModelConfigProvider>();
    final ocrModel = _findModelConfigById(mp.models, modelId);
    if (ocrModel == null) {
      throw Exception('OCR 模型已不存在，请在设置中重新选择');
    }
    final results = <String>[];
    for (final image in files.where((file) => file.isImage)) {
      try {
        final bytes = await File(image.path).readAsBytes();
        final text = await _api.recognizeImageText(ocrModel, bytes);
        final clean = text.trim();
        if (clean.isNotEmpty) results.add(clean);
      } catch (e) {
        results.add('[${image.name} OCR 识别失败: $e]');
      }
    }
    return results.join('\n');
  }

  Future<Object> _directModelContent(
    String text,
    List<MessageImage> files,
  ) async {
    if (files.isEmpty) return text;
    final inputs = <ChatFileInput>[];
    for (final file in files) {
      inputs.add(
        ChatFileInput(
          bytes: await File(file.path).readAsBytes(),
          mimeType: file.mimeType,
          name: file.name,
        ),
      );
    }
    return ApiService.chatContentWithFiles(text, inputs);
  }

  String _mimeTypeForPath(String path, {String? fallbackPath}) {
    final lower = path.toLowerCase();
    final fallback = fallbackPath?.toLowerCase();
    bool endsWith(String extension) {
      return lower.endsWith(extension) ||
          (fallback?.endsWith(extension) ?? false);
    }

    if (endsWith('.png')) return 'image/png';
    if (endsWith('.jpg') || endsWith('.jpeg')) return 'image/jpeg';
    if (endsWith('.webp')) return 'image/webp';
    if (endsWith('.gif')) return 'image/gif';
    if (endsWith('.pdf')) return 'application/pdf';
    if (endsWith('.txt') || endsWith('.md')) return 'text/plain';
    if (endsWith('.json')) return 'application/json';
    if (endsWith('.csv')) return 'text/csv';
    if (endsWith('.html') || endsWith('.htm')) return 'text/html';
    if (endsWith('.xml')) return 'application/xml';
    if (endsWith('.zip')) return 'application/zip';
    if (endsWith('.doc')) return 'application/msword';
    if (endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (endsWith('.xls')) return 'application/vnd.ms-excel';
    if (endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }

  Future<void> _voice() async {
    if (_streaming || _recording || _transcribingSpeech) return;
    final speechModelId =
        _activeSettings()?.speechModelId ??
        context.read<SettingsProvider>().settings.speechModelId;
    if (speechModelId == null || speechModelId.isEmpty) {
      await _startSystemSpeechRecognition();
      return;
    }
    await _startAudioRecording();
  }

  Future<void> _startAudioRecording() async {
    final hasPermission = await _audioRecorder.hasPermission();
    if (!mounted) return;
    if (!hasPermission) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('没有麦克风权限，请在系统设置中允许录音权限')));
      return;
    }
    try {
      final dir = await getTemporaryDirectory();
      final path =
          '${dir.path}/lynai_${DateTime.now().millisecondsSinceEpoch}.m4a';
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted) return;
      setState(() {
        _recording = true;
        _recordPath = path;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _recording = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('录音启动失败: $e')));
    }
  }

  /// 系统语音识别仅负责把结果写入输入框，不直接发送消息。
  ///
  /// 这样用户可以在发送前修正识别错误，也和自定义语音转文字接口保持一致。
  Future<void> _startSystemSpeechRecognition() async {
    final ok = await _speech.initialize(
      onStatus: (s) {
        if (!mounted) return;
        if (s == 'done' || s == 'notListening') {
          setState(() => _recording = false);
        }
      },
      onError: (_) {
        if (!mounted) return;
        setState(() => _recording = false);
      },
    );
    if (!mounted) return;
    final locale = Localizations.localeOf(context);
    final localeId =
        '${locale.languageCode}_${locale.countryCode ?? locale.languageCode.toUpperCase()}';
    if (ok) {
      setState(() => _recording = true);
      try {
        _speech.listen(
          onResult: (r) {
            if (!mounted) return;
            _msgCtrl.text = r.recognizedWords;
            if (r.finalResult) {
              setState(() => _recording = false);
              _fillSpeechText(r.recognizedWords);
            }
          },
          localeId: localeId,
        );
      } catch (_) {
        setState(() => _recording = false);
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('语音监听启动失败')));
        }
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('语音功能初始化失败，请检查麦克风权限')));
      }
    }
  }

  void _fillSpeechText(String txt) {
    final text = txt.trim();
    if (text.isEmpty) return;
    final current = _msgCtrl.text.trim();
    _msgCtrl.text = current.isEmpty ? text : '$current\n$text';
    _msgCtrl.selection = TextSelection.collapsed(offset: _msgCtrl.text.length);
    _focusNode.requestFocus();
    setState(() {});
  }

  Future<void> _processRecordedSpeech(String path) async {
    final mp = context.read<ModelConfigProvider>();
    final speechConfigId =
        _activeSettings()?.speechModelId ??
        context.read<SettingsProvider>().settings.speechModelId;
    if (speechConfigId == null || speechConfigId.isEmpty) return;
    final speechConfig = _findModelConfigById(mp.models, speechConfigId);
    if (speechConfig == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('语音转文字接口不存在，请在设置中重新选择')));
      return;
    }
    setState(() => _transcribingSpeech = true);
    try {
      final bytes = await File(path).readAsBytes();
      final text = await _api.transcribeAudio(speechConfig, bytes);
      if (!mounted) return;
      if (text.trim().isEmpty) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('语音未识别到文字')));
      } else {
        _fillSpeechText(text);
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('语音转文字失败: $e')));
    } finally {
      if (mounted) setState(() => _transcribingSpeech = false);
      File(path).delete().catchError((_) => File(path));
    }
  }

  Future<void> _stopVoice() async {
    if (_recordPath != null) {
      String? path;
      try {
        path = await _audioRecorder.stop();
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('录音停止失败: $e')));
        }
      }
      if (!mounted) return;
      final recordPath = path ?? _recordPath;
      setState(() {
        _recording = false;
        _recordPath = null;
      });
      if (recordPath != null) await _processRecordedSpeech(recordPath);
      return;
    }
    await _speech.stop();
    if (mounted) setState(() => _recording = false);
  }

  void _selectHistory(String cid) {
    if (_streaming && cid != _streamingConvId) {
      _stopStreaming();
    }
    _clearRetryState();
    _pendingModelId = null;
    _expandedThinkIds.clear();
    _thinkMap.clear();
    setState(() {
      _convId = cid.isEmpty ? null : cid;
      _thinkingTxt = null;
      _thinkExpanded = false;
    });
    if (cid.isNotEmpty) {
      _applyConversationSettings(cid);
    }
    Navigator.pop(context);
  }

  String _fmtSz(int b) {
    if (b < 1024) return '$b B';
    if (b < 1048576) return '${(b / 1024).toStringAsFixed(1)} KB';
    return '${(b / 1048576).toStringAsFixed(1)} MB';
  }

  void _showDialogSettings() {
    final model = _getModel(context.read<ModelConfigProvider>());
    if (model == null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('请先在设置中添加 AI 模型')));
      return;
    }
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => _DialogSettingsContent(
        onChanged: (settings) => _saveConversationSettings(settings),
        settings: _currentConversationSettings(model),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<ConversationProvider>();
    final mp = context.watch<ModelConfigProvider>();
    final model = _getModel(mp);
    final conv = cp.getConversation(_convId ?? '');
    return PopScope(
      canPop: !_shareSelecting,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _shareSelecting) _cancelShareSelection();
      },
      child: Scaffold(
        appBar: AppBar(
          leading: _shareSelecting
              ? IconButton(
                  icon: const Icon(Icons.close),
                  tooltip: '取消选择',
                  onPressed: _cancelShareSelection,
                )
              : Builder(
                  builder: (ctx) => IconButton(
                    icon: const Icon(Icons.history),
                    tooltip: '历史记录',
                    onPressed: () => Scaffold.of(ctx).openDrawer(),
                  ),
                ),
          title: Text(
            _shareSelecting
                ? '已选择 ${_selectedShareMessageIds.length} 条'
                : (conv?.title ?? '新对话'),
          ),
          centerTitle: true,
          actions: [
            if (_shareSelecting)
              IconButton(
                icon: const Icon(Icons.save_alt),
                tooltip: '保存到本地',
                onPressed: _selectedShareMessageIds.isEmpty || _sharingImage
                    ? null
                    : _saveSelectedMessagesImage,
              ),
            if (_shareSelecting)
              IconButton(
                icon: _sharingImage
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.ios_share),
                tooltip: '生成长图分享',
                onPressed: _selectedShareMessageIds.isEmpty || _sharingImage
                    ? null
                    : _shareSelectedMessages,
              )
            else if (_convId != null)
              IconButton(
                icon: const Icon(Icons.add_comment_outlined),
                tooltip: '新建对话',
                onPressed: () {
                  if (_streaming) _stopStreaming();
                  _clearRetryState();
                  _clearPendingState();
                  setState(() {
                    _convId = null;
                  });
                },
              ),
          ],
        ),
        drawer: _shareSelecting ? null : _drawer(context),
        body: Screenshot(
          controller: _screenshotCtrl,
          child: _body(conv, model, mp),
        ),
      ),
    );
  }

  Widget _drawer(BuildContext ctx) => Drawer(
    child: _HistoryDrawer(onSelect: _selectHistory, currentConvId: _convId),
  );

  Widget _body(Conversation? conv, ModelConfig? model, ModelConfigProvider mp) {
    final msgs = conv != null ? conv.messages.toList() : <Message>[];
    int lastUserIdx = -1;
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == 'user') {
        lastUserIdx = i;
        break;
      }
    }
    return Column(
      children: [
        Expanded(
          child: Stack(
            children: [
              msgs.isEmpty
                  ? _empty()
                  : NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: ListView.builder(
                        controller: _scrollCtrl,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 8,
                        ),
                        itemCount: msgs.length,
                        itemBuilder: (_, i) {
                          final msg = msgs[i];
                          return _selectableBubble(
                            msg,
                            i == msgs.length - 1,
                            i == lastUserIdx,
                          );
                        },
                      ),
                    ),
              if (_showScrollToBottom) _scrollToBottomButton(),
              if (_showModelMenu) _floatingModelList(mp),
            ],
          ),
        ),
        _inputArea(model, mp),
      ],
    );
  }

  Widget _scrollToBottomButton() {
    return Positioned(
      right: 16,
      bottom: 12,
      child: Material(
        color: Theme.of(context).colorScheme.primary,
        shape: const CircleBorder(),
        elevation: 3,
        child: InkWell(
          onTap: _jumpToBottom,
          customBorder: const CircleBorder(),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Icon(
              Icons.keyboard_arrow_down_rounded,
              color: Theme.of(context).colorScheme.onPrimary,
              size: 24,
            ),
          ),
        ),
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(Icons.chat_bubble_outline, size: 80, color: Colors.grey[300]),
        const SizedBox(height: 16),
        Text(
          '开始新对话',
          style: TextStyle(
            fontSize: 20,
            color: Colors.grey[500],
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '在下方输入你的问题',
          style: TextStyle(fontSize: 14, color: Colors.grey[400]),
        ),
      ],
    ),
  );

  Widget _selectableBubble(Message msg, bool isLastAi, bool isLastUserMsg) {
    final selected = _selectedShareMessageIds.contains(msg.id);
    final bubble = _bubble(msg, isLastAi, isLastUserMsg);
    if (!_shareSelecting) return bubble;
    return InkWell(
      onTap: () => _toggleShareMessage(msg),
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 2),
        decoration: BoxDecoration(
          color: selected
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.08)
              : null,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.35)
                : Colors.transparent,
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Padding(
              padding: const EdgeInsets.only(left: 6),
              child: Icon(
                selected ? Icons.check_circle : Icons.circle_outlined,
                size: 20,
                color: selected
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[400],
              ),
            ),
            Expanded(child: bubble),
          ],
        ),
      ),
    );
  }

  Widget _bubble(Message msg, bool isLastAi, bool isLastUserMsg) {
    final u = msg.role == 'user';
    if (u) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 10,
                    ),
                    constraints: BoxConstraints(
                      maxWidth: MediaQuery.of(context).size.width * 0.65,
                    ),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.primaryContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.04),
                          blurRadius: 4,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (msg.content.isNotEmpty)
                          SelectableText(
                            msg.content,
                            style: const TextStyle(fontSize: 15),
                          ),
                        if (msg.images.isNotEmpty && msg.content.isNotEmpty)
                          const SizedBox(height: 8),
                        if (msg.images.isNotEmpty) _messageImages(msg.images),
                      ],
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                if (!_shareSelecting)
                  InkWell(
                    onTap: () => _showEditDialog(msg, isLastUserMsg),
                    borderRadius: BorderRadius.circular(12),
                    child: Padding(
                      padding: const EdgeInsets.all(4),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 16,
                        color: Colors.grey[400],
                      ),
                    ),
                  ),
              ],
            ),
            if (!_shareSelecting &&
                isLastUserMsg &&
                _retryMsgId != null &&
                _retryHistory.length > 1)
              _retryNav(),
          ],
        ),
      );
    }
    final thinkForMsg = isLastAi
        ? (_thinkingTxt != null && _thinkingTxt!.isNotEmpty
              ? _thinkingTxt
              : _thinkForMessage(msg))
        : _thinkForMessage(msg);
    final missingThinkNotice = _missingThinkNotice(msg, isLastAi);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thinkForMsg != null && thinkForMsg.isNotEmpty)
          _thinkSection(thinkForMsg),
        if (thinkForMsg == null && missingThinkNotice != null)
          _thinkSection(missingThinkNotice),
        if (!isLastAi) ..._buildPerMsgThinkSection(msg),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.85,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: msg.content.isEmpty && _streaming
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : MarkdownWithLatex(content: msg.content),
        ),
        if (!_streaming && !_shareSelecting) _bubbleActions(msg, isLastAi),
      ],
    );
  }

  Widget _messageImages(List<MessageImage> images) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: images.map((image) {
        final exists = File(image.path).existsSync();
        if (!image.isImage) {
          return _fileChip(image, exists: exists);
        }
        return InkWell(
          onTap: exists
              ? () => _showImagePreview(image.path, image.name)
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: exists
                ? Image.file(
                    File(image.path),
                    width: 120,
                    height: 120,
                    fit: BoxFit.cover,
                  )
                : Container(
                    width: 120,
                    height: 60,
                    alignment: Alignment.center,
                    color: Colors.black.withValues(alpha: 0.08),
                    child: const Text('文件已不存在', style: TextStyle(fontSize: 12)),
                  ),
          ),
        );
      }).toList(),
    );
  }

  Widget _fileChip(MessageImage file, {required bool exists}) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 160,
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Row(
        children: [
          Icon(_fileIcon(file.mimeType), color: scheme.primary, size: 22),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  file.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  exists ? _fmtSz(file.size) : '文件已不存在',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _showImagePreview(String path, String name) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: const EdgeInsets.all(12),
        backgroundColor: Colors.black,
        child: Stack(
          children: [
            InteractiveViewer(
              child: Center(child: Image.file(File(path), fit: BoxFit.contain)),
            ),
            Positioned(
              right: 8,
              top: 8,
              child: IconButton(
                onPressed: () => Navigator.pop(ctx),
                icon: const Icon(Icons.close, color: Colors.white),
                tooltip: '关闭',
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _thinkSection([String? think]) {
    final content = think ?? _thinkingTxt;
    if (content == null || content.isEmpty) return const SizedBox.shrink();
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(
              context,
            ).colorScheme.secondary.withValues(alpha: 0.3),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _thinkExpanded = !_thinkExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _thinkExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 14,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '思考过程',
                    style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                  ),
                ],
              ),
            ),
          ),
          if (_thinkExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Text(
                content,
                style: TextStyle(
                  fontSize: 13,
                  color: Colors.grey[500],
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  String? _thinkForMessage(Message msg) {
    final fromMap = _thinkMap[msg.id];
    if (fromMap != null && fromMap.isNotEmpty) return fromMap;
    final fromMessage = msg.thinkingContent;
    if (fromMessage != null && fromMessage.isNotEmpty) return fromMessage;
    return null;
  }

  String? _missingThinkNotice(Message msg, bool isLastAi) {
    if (!_thinking ||
        !isLastAi ||
        msg.role != 'assistant' ||
        msg.content.trim().isEmpty) {
      return null;
    }
    if (_streaming && isLastAi) return '正在等待模型返回可见思考过程...';
    if (msg.content.startsWith('请求失败') ||
        msg.content.startsWith('图片处理失败') ||
        msg.content.startsWith('文件处理失败')) {
      return null;
    }
    return '当前模型或 API 没有返回可见思考过程。部分模型会进行内部推理，但不会向客户端暴露 reasoning/thinking 字段，因此无法显示真实思考过程。';
  }

  List<Widget> _buildPerMsgThinkSection(Message msg) {
    final think = _thinkForMessage(msg);
    if (think == null || think.isEmpty) return [];
    final expanded = _expandedThinkIds.contains(msg.id);
    return [
      Container(
        margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
        decoration: BoxDecoration(
          border: Border(
            left: BorderSide(
              color: Theme.of(
                context,
              ).colorScheme.secondary.withValues(alpha: 0.3),
              width: 2,
            ),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => setState(() {
                if (expanded) {
                  _expandedThinkIds.remove(msg.id);
                } else {
                  _expandedThinkIds.add(msg.id);
                }
              }),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      expanded ? Icons.expand_less : Icons.expand_more,
                      size: 14,
                      color: Colors.grey[500],
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '思考过程',
                      style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                    ),
                  ],
                ),
              ),
            ),
            if (expanded)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Text(
                  think,
                  style: TextStyle(
                    fontSize: 13,
                    color: Colors.grey[500],
                    fontStyle: FontStyle.italic,
                    height: 1.4,
                  ),
                ),
              ),
          ],
        ),
      ),
    ];
  }

  Widget _actions(Message msg, {required bool canRetry}) => Padding(
    padding: const EdgeInsets.only(left: 8, top: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actBtn(Icons.copy, () => _copy(msg.content)),
        const SizedBox(width: 4),
        _actBtn(Icons.share, () => _startShareSelection(msg)),
        if (canRetry) ...[
          const SizedBox(width: 4),
          _actBtn(Icons.refresh, () => unawaited(_retry())),
        ],
      ],
    ),
  );

  Widget _retryOnlyAction() => Padding(
    padding: const EdgeInsets.only(left: 8, top: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actBtn(Icons.refresh, () => unawaited(_retryWithoutHistory())),
      ],
    ),
  );

  Widget _bubbleActions(Message msg, bool canRetry) {
    if (msg.content.isEmpty ||
        msg.content.startsWith('请求失败') ||
        msg.content.startsWith('流式请求失败')) {
      return canRetry ? _retryOnlyAction() : const SizedBox.shrink();
    }
    return _actions(msg, canRetry: canRetry);
  }

  Widget _actBtn(IconData i, VoidCallback t) => InkWell(
    onTap: t,
    borderRadius: BorderRadius.circular(12),
    child: Padding(
      padding: const EdgeInsets.all(4),
      child: Icon(i, size: 16, color: Colors.grey[400]),
    ),
  );

  Widget _retryNav() {
    final total = _retryHistory.length;
    final current = _retryIdx;
    if (total <= 1) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            onTap: current > 0 ? () => _switchRetry(-1) : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                '<',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: current > 0
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[300],
                ),
              ),
            ),
          ),
          Text(
            '${current + 1}/$total',
            style: TextStyle(
              fontSize: 11,
              color: Colors.grey[500],
              fontFamily: 'monospace',
            ),
          ),
          InkWell(
            onTap: current < total - 1 ? () => _switchRetry(1) : null,
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                '>',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: current < total - 1
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[300],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _switchRetry(int direction) {
    if (_convId == null || _retryMsgId == null) return;
    final cp = context.read<ConversationProvider>();
    final newIdx = (_retryIdx + direction).clamp(0, _retryHistory.length - 1);
    if (newIdx == _retryIdx) return;
    _retryIdx = newIdx;
    final entry = _retryHistory[newIdx];
    cp.updateMessageContent(_convId!, _retryMsgId!, entry.userContent);
    cp.updateMessageImages(_convId!, _retryMsgId!, entry.userImages);
    final conv = cp.getConversation(_convId!);
    if (conv == null) return;
    final lastAssistant = conv.messages
        .where((m) => m.role == 'assistant')
        .toList();
    if (entry.assistantContent != null && entry.assistantContent!.isNotEmpty) {
      if (lastAssistant.isNotEmpty) {
        cp.updateMessageContent(
          _convId!,
          lastAssistant.last.id,
          entry.assistantContent!,
        );
        if (entry.thinkingContent != null) {
          _thinkMap[lastAssistant.last.id] = entry.thinkingContent;
        } else {
          _thinkMap.remove(lastAssistant.last.id);
        }
      } else {
        cp.addMessage(
          _convId!,
          'assistant',
          entry.assistantContent!,
          thinkingContent: entry.thinkingContent,
        );
      }
      _thinkingTxt = entry.thinkingContent;
    } else {
      if (lastAssistant.isNotEmpty) {
        cp.updateMessageContent(_convId!, lastAssistant.last.id, '');
        _thinkMap.remove(lastAssistant.last.id);
      }
      _thinkingTxt = null;
    }
    setState(() {
      _setStreaming(false);
    });
    _scrollEnd();
  }

  void _showEditDialog(Message msg, bool isLastUserMsg) {
    final ctrl = TextEditingController(text: msg.content);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(isLastUserMsg ? '编辑消息' : '从此处开始新对话'),
        content: TextField(
          controller: ctrl,
          maxLines: 5,
          minLines: 1,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '编辑消息内容...',
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final text = ctrl.text.trim();
              Navigator.pop(ctx);
              if (text.isEmpty) return;
              if (isLastUserMsg) {
                unawaited(_sendRetry(text));
              } else {
                unawaited(_editStartNewConversation(msg, text));
              }
            },
            child: Text(isLastUserMsg ? '发送' : '开始新对话'),
          ),
        ],
      ),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    });
  }

  Future<void> _editStartNewConversation(
    Message origMsg,
    String newText,
  ) async {
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    final editModel = _getModel(mp);
    if (editModel == null || _convId == null) {
      if (editModel == null) _showMissingChatModelTip();
      return;
    }
    final origConv = cp.getConversation(_convId!);
    if (origConv == null) return;
    final allMsgs = origConv.messages;
    final origMsgIdx = allMsgs.indexWhere((m) => m.id == origMsg.id);
    if (origMsgIdx == -1) return;
    final apiUserContent = await _prepareUserContent(newText, origMsg.images);
    if (!mounted || apiUserContent == null) return;
    _clearRetryState();
    _pendingModelId = null;
    final newConvId = cp.createConversation(
      origConv.settings.copyWith(modelId: editModel.id, thinking: _thinking),
      roleId: origConv.roleId,
    );
    for (int i = 0; i < origMsgIdx; i++) {
      cp.addMessage(
        newConvId,
        allMsgs[i].role,
        allMsgs[i].content,
        images: allMsgs[i].images,
        thinkingContent: allMsgs[i].thinkingContent,
      );
    }
    cp.addMessage(newConvId, 'user', newText, images: origMsg.images);
    setState(() {
      _convId = newConvId;
      _clearPendingState();
      _beginStreaming(newConvId);
    });
    _scrollEnd();
    cp.addMessage(newConvId, 'assistant', '');
    _doSend(editModel, lastUserContentOverride: apiUserContent);
  }

  Widget _inputArea(ModelConfig? model, ModelConfigProvider mp) {
    final set = _activeSettings();
    final appSettings = context.watch<SettingsProvider>().settings;
    final speechModelId = set?.speechModelId ?? appSettings.speechModelId;
    final hasSpeech = speechModelId != null && speechModelId.isNotEmpty;
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 4,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.only(
        left: 8,
        right: 8,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (_pendingImages.isNotEmpty) _pendingImagePreview(),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: _transcribingSpeech
                    ? _transcribingOverlay()
                    : _recording
                    ? _recOverlay()
                    : Focus(
                        onKeyEvent: (node, event) {
                          if (event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.enter &&
                              !HardwareKeyboard.instance.isShiftPressed) {
                            _send();
                            return KeyEventResult.handled;
                          }
                          final isPaste =
                              event is KeyDownEvent &&
                              event.logicalKey == LogicalKeyboardKey.keyV &&
                              (HardwareKeyboard.instance.isControlPressed ||
                                  HardwareKeyboard.instance.isMetaPressed);
                          if (isPaste) {
                            unawaited(_handlePasteShortcut());
                            return KeyEventResult.handled;
                          }
                          return KeyEventResult.ignored;
                        },
                        child: TextField(
                          controller: _msgCtrl,
                          focusNode: _focusNode,
                          style: const TextStyle(fontSize: 16),
                          decoration: const InputDecoration(
                            hintText: '输入消息...',
                            border: InputBorder.none,
                            contentPadding: EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 10,
                            ),
                          ),
                          maxLines: 5,
                          minLines: 1,
                          textInputAction: TextInputAction.newline,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _modelSel(model, mp),
              const SizedBox(width: 4),
              _dialogSetBtn(),
              const SizedBox(width: 4),
              _thinkBtn(),
              const SizedBox(width: 4),
              _ocrBtn(),
              const SizedBox(width: 4),
              _imageRecognitionBtn(),
              const Spacer(),
              _attachBtn(),
              const SizedBox(width: 4),
              _voiceOrSendBtn(hasSpeech),
            ],
          ),
          if (_showAttach) _attachMenu(),
        ],
      ),
    );
  }

  Widget _modelList(ModelConfigProvider mp) {
    final cur = _getModel(mp);
    final models = mp.modelsByCategory(ModelConfig.categoryChat);
    final settings = _activeSettings();
    return Container(
      margin: EdgeInsets.zero,
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: Theme.of(
            context,
          ).colorScheme.outlineVariant.withValues(alpha: 0.8),
        ),
      ),
      child: ListView(
        shrinkWrap: true,
        children: [
          for (final m in models) ...[
            Builder(
              builder: (_) {
                final sel = cur != null && m.id == cur.id;
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    ListTile(
                      dense: true,
                      leading: Icon(
                        sel ? Icons.check_circle : Icons.circle_outlined,
                        size: 18,
                        color: sel
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey,
                      ),
                      title: Text(
                        m.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: Text(
                        m.hasMultipleModels
                            ? '${m.enabledModelNames.length} 个模型'
                            : m.modelName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 11),
                      ),
                      trailing: m.hasMultipleModels
                          ? const Icon(Icons.chevron_right, size: 16)
                          : null,
                      onTap: () {
                        if (m.hasMultipleModels) {
                          _switchModel(m);
                        } else {
                          _switchModel(m);
                          setState(() => _showModelMenu = false);
                        }
                      },
                    ),
                    if (sel && m.hasMultipleModels)
                      ...m.models
                          .where((e) => e.enabled)
                          .map(
                            (e) => ListTile(
                              dense: true,
                              contentPadding: const EdgeInsets.only(left: 56),
                              leading: Icon(
                                e.name == m.modelName
                                    ? Icons.radio_button_checked
                                    : Icons.radio_button_off,
                                size: 14,
                                color: e.name == m.modelName
                                    ? Theme.of(context).colorScheme.primary
                                    : Colors.grey,
                              ),
                              title: Text(
                                e.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 13,
                                  fontFamily: 'monospace',
                                ),
                              ),
                              onTap: () {
                                _setSubModel(m, e.name);
                                setState(() => _showModelMenu = false);
                              },
                            ),
                          ),
                  ],
                );
              },
            ),
          ],
          const Divider(height: 1),
          ListTile(
            dense: true,
            leading: Icon(
              Icons.file_present_outlined,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('文件识别', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '选择聊天模型作为文件识别模型',
              style: TextStyle(fontSize: 11),
            ),
            trailing: Icon(
              _showImageRecognitionList ? Icons.expand_less : Icons.expand_more,
              size: 16,
            ),
            onTap: () {
              setState(() {
                _showImageRecognitionList = !_showImageRecognitionList;
              });
            },
          ),
          if (_showImageRecognitionList)
            for (final m in models.where(_hasVisionModel))
              ListTile(
                dense: true,
                contentPadding: const EdgeInsets.only(left: 56),
                leading: Icon(
                  settings?.imageRecognitionModelId == m.id
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  size: 14,
                  color: settings?.imageRecognitionModelId == m.id
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey,
                ),
                title: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 13),
                ),
                subtitle: Text(
                  m.hasMultipleModels
                      ? '${_enabledVisionEntries(m).length} 个视觉模型'
                      : m.modelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  final next = _ensureVisionModel(m);
                  final base = _currentConversationSettings(cur ?? m);
                  _saveConversationSettings(
                    base.copyWith(imageRecognitionModelId: next.id),
                  );
                  if (next.modelName != m.modelName) {
                    context.read<ModelConfigProvider>().updateModel(next);
                  }
                  setState(() => _showImageRecognitionList = false);
                },
              ),
        ],
      ),
    );
  }

  Widget _floatingModelList(ModelConfigProvider mp) {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 8,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: _modelList(mp),
      ),
    );
  }

  List<ModelEntry> _enabledVisionEntries(ModelConfig config) {
    return config.models
        .where((entry) => entry.enabled && entry.supportsVision)
        .toList(growable: false);
  }

  bool _hasVisionModel(ModelConfig config) =>
      _enabledVisionEntries(config).isNotEmpty;

  ModelConfig _ensureVisionModel(ModelConfig config) {
    final active = config.activeEntry;
    if (active != null && active.enabled && active.supportsVision) {
      return config;
    }
    final entries = _enabledVisionEntries(config);
    return entries.isEmpty
        ? config
        : config.copyWith(modelName: entries.first.name);
  }

  Widget _modelSel(ModelConfig? cur, ModelConfigProvider mp) {
    final width = MediaQuery.sizeOf(context).width;
    final hideName = width < 430;
    final maxWidth = width < 520 ? 136.0 : 220.0;
    if (cur == null) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: const Icon(Icons.smart_toy, size: 18, color: Colors.grey),
      );
    }
    if (_showModelMenu) {
      return InkWell(
        onTap: () => setState(() => _showModelMenu = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.1),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Icon(
            Icons.smart_toy,
            size: 18,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
      );
    }
    return InkWell(
      onTap: () => setState(() => _showModelMenu = true),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: hideName ? 38 : maxWidth),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.3),
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.smart_toy,
                size: 16,
                color: Theme.of(context).colorScheme.primary,
              ),
              if (!hideName) ...[
                const SizedBox(width: 4),
                Flexible(
                  child: Text(
                    cur.modelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  void _expandInputAction(String id) {
    _inputActionCollapseTimer?.cancel();
    setState(() => _expandedInputAction = id);
    _inputActionCollapseTimer = Timer(const Duration(seconds: 5), () {
      if (mounted && _expandedInputAction == id) {
        setState(() => _expandedInputAction = null);
      }
    });
  }

  void _collapseInputAction(String id) {
    if (!_isDesktopPlatform) return;
    _inputActionCollapseTimer?.cancel();
    if (_expandedInputAction == id) {
      setState(() => _expandedInputAction = null);
    }
  }

  Widget _inputActionButton({
    required String id,
    required IconData icon,
    required String label,
    required bool selected,
    required VoidCallback? onPressed,
  }) {
    final expanded = _expandedInputAction == id;
    final scheme = Theme.of(context).colorScheme;
    final enabled = onPressed != null;
    final foreground = !enabled
        ? Colors.grey[300]
        : selected
        ? scheme.primary
        : Colors.grey[500];
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 32),
      padding: EdgeInsets.symmetric(horizontal: expanded ? 9 : 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected ? scheme.primary : Colors.grey.withValues(alpha: 0.3),
        ),
        color: selected ? scheme.primary.withValues(alpha: 0.1) : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 18, color: foreground),
          if (expanded) ...[
            const SizedBox(width: 4),
            Text(label, style: TextStyle(fontSize: 12, color: foreground)),
          ],
        ],
      ),
    );
    return MouseRegion(
      onEnter: (_) {
        if (_isDesktopPlatform) _expandInputAction(id);
      },
      onExit: (_) => _collapseInputAction(id),
      child: InkWell(
        onTap: onPressed == null
            ? null
            : () {
                _expandInputAction(id);
                onPressed();
              },
        borderRadius: BorderRadius.circular(8),
        child: child,
      ),
    );
  }

  Widget _dialogSetBtn() => _inputActionButton(
    id: 'settings',
    icon: Icons.tune,
    label: '设置',
    selected: false,
    onPressed: _showDialogSettings,
  );

  Widget _thinkBtn() {
    final model = _getModel(context.read<ModelConfigProvider>());
    final available = model == null || _supportsThinking(model);
    return _inputActionButton(
      id: 'thinking',
      icon: Icons.psychology,
      label: '思考',
      selected: _thinking && available,
      onPressed: available
          ? () {
              final value = !_thinking;
              setState(() => _thinking = value);
              if (_convId != null) {
                final conv = context
                    .read<ConversationProvider>()
                    .getConversation(_convId!);
                if (conv != null) {
                  _saveConversationSettings(
                    conv.settings.copyWith(thinking: value),
                  );
                }
              } else if (_draftSettings != null) {
                _saveDraftSettings(_draftSettings!.copyWith(thinking: value));
              }
            }
          : null,
    );
  }

  Widget _ocrBtn() {
    final enabled =
        _activeSettings()?.imageOcrEnabled ??
        context.watch<SettingsProvider>().settings.imageOcrEnabled;
    return _inputActionButton(
      id: 'ocr',
      icon: Icons.document_scanner_outlined,
      label: 'OCR',
      selected: enabled,
      onPressed: () {
        final value = !enabled;
        final model = _getModel(context.read<ModelConfigProvider>());
        if (model == null) return;
        final settings = _currentConversationSettings(
          model,
        ).copyWith(imageOcrEnabled: value);
        setState(() {});
        _saveConversationSettings(settings);
      },
    );
  }

  Widget _imageRecognitionBtn() {
    final enabled =
        _activeSettings()?.imageRecognitionEnabled ??
        context.watch<SettingsProvider>().settings.imageRecognitionEnabled;
    return _inputActionButton(
      id: 'fileRecognition',
      icon: Icons.file_present_outlined,
      label: '文件识别',
      selected: enabled,
      onPressed: () {
        final value = !enabled;
        final model = _getModel(context.read<ModelConfigProvider>());
        if (model == null) return;
        final settings = _currentConversationSettings(
          model,
        ).copyWith(imageRecognitionEnabled: value);
        setState(() {});
        _saveConversationSettings(settings);
      },
    );
  }

  Widget _attachBtn() => InkWell(
    onTap: () => setState(() => _showAttach = !_showAttach),
    borderRadius: BorderRadius.circular(12),
    child: Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        color: _showAttach
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : null,
      ),
      child: Icon(
        Icons.add,
        size: 22,
        color: _showAttach
            ? Theme.of(context).colorScheme.primary
            : Colors.grey[500],
      ),
    ),
  );

  Widget _attachMenu() => Padding(
    padding: const EdgeInsets.only(top: 8),
    child: Row(
      mainAxisAlignment: MainAxisAlignment.end,
      children: [
        _attachOpt(Icons.attach_file, '文件', () {
          setState(() => _showAttach = false);
          _pickFiles();
        }),
        const SizedBox(width: 8),
        _attachOpt(Icons.photo_library, '图片', () {
          setState(() => _showAttach = false);
          _pickImg();
        }),
        if (!_isDesktopPlatform) ...[
          const SizedBox(width: 8),
          _attachOpt(Icons.photo_camera, '拍照', () {
            setState(() => _showAttach = false);
            _takePhoto();
          }),
        ],
      ],
    ),
  );

  Widget _attachOpt(IconData i, String l, VoidCallback t) => InkWell(
    onTap: t,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(i, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 4),
          Text(l, style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    ),
  );

  Widget _pendingImagePreview() {
    return Container(
      height: 86,
      alignment: Alignment.centerLeft,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: _pendingImages.length,
        separatorBuilder: (_, _) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final image = _pendingImages[index];
          return Stack(
            children: [
              InkWell(
                onTap: image.isImage
                    ? () => _showImagePreview(image.path, image.name)
                    : null,
                child: _pendingAttachmentPreview(image),
              ),
              Positioned(
                right: 2,
                top: 2,
                child: InkWell(
                  onTap: () => setState(() => _pendingImages.removeAt(index)),
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      shape: BoxShape.circle,
                    ),
                    padding: const EdgeInsets.all(2),
                    child: const Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 14,
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _pendingAttachmentPreview(_PendingImage file) {
    if (file.mimeType.startsWith('image/')) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Image.file(
          File(file.path),
          width: 76,
          height: 76,
          fit: BoxFit.cover,
        ),
      );
    }
    final scheme = Theme.of(context).colorScheme;
    return Container(
      width: 120,
      height: 76,
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(_fileIcon(file.mimeType), size: 22, color: scheme.primary),
          const Spacer(),
          Text(
            file.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
          ),
          Text(
            _fmtSz(file.size),
            style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }

  IconData _fileIcon(String mimeType) {
    if (mimeType.startsWith('image/')) return Icons.image_outlined;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mimeType.startsWith('text/') || mimeType == 'application/json') {
      return Icons.description_outlined;
    }
    if (mimeType.contains('zip') || mimeType.contains('compressed')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  Widget _voiceOrSendBtn(bool hasSpeech) {
    if (_streaming) {
      return IconButton(
        onPressed: _stopStreaming,
        tooltip: '停止生成',
        icon: Icon(Icons.stop_circle, color: Colors.red[400], size: 24),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );
    }
    final canSend =
        _msgCtrl.text.trim().isNotEmpty || _pendingImages.isNotEmpty;
    if (_transcribingSpeech) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }
    if (_recording) {
      return GestureDetector(
        onLongPressEnd: (_) => _stopVoice(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.red,
            borderRadius: BorderRadius.circular(20),
          ),
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.stop, size: 16, color: Colors.white),
              SizedBox(width: 4),
              Text(
                '松开转文字',
                style: TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    if (canSend) {
      return IconButton(
        onPressed: _send,
        icon: Icon(
          Icons.send_rounded,
          color: Theme.of(context).colorScheme.primary,
          size: 22,
        ),
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      );
    }
    return GestureDetector(
      onLongPressStart: (_) => _voice(),
      onLongPressEnd: (_) => _stopVoice(),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(
          hasSpeech ? Icons.mic_none : Icons.mic_none_outlined,
          size: 22,
          color: Colors.grey[500],
        ),
      ),
    );
  }

  Widget _transcribingOverlay() => Container(
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(12),
      border: Border.all(
        color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.18),
      ),
    ),
    child: Row(
      children: [
        SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Text(
          '正在转文字...',
          style: TextStyle(
            color: Theme.of(context).colorScheme.primary,
            fontSize: 14,
          ),
        ),
      ],
    ),
  );

  Widget _recOverlay() => GestureDetector(
    onLongPressEnd: (_) => _stopVoice(),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.red.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(Icons.mic, size: 20, color: Colors.red[400]),
          const SizedBox(width: 8),
          Text(
            _speech.isListening ? '正在聆听...' : '正在录音，松开转文字',
            style: TextStyle(color: Colors.red[400], fontSize: 14),
          ),
        ],
      ),
    ),
  );
}

ModelConfig? _findModelConfigById(List<ModelConfig> models, String id) {
  try {
    return models.firstWhere((m) => m.id == id);
  } catch (_) {
    return null;
  }
}

class _ShareConversationImage extends StatelessWidget {
  final String title;
  final List<Message> messages;
  final Color seedColor;
  final Brightness brightness;
  final int? pageNumber;
  final int? pageCount;

  const _ShareConversationImage({
    required this.title,
    required this.messages,
    required this.seedColor,
    required this.brightness,
    this.pageNumber,
    this.pageCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final bgColor = Color.lerp(
      scheme.surface,
      scheme.primary,
      isDark ? 0.08 : 0.035,
    )!;
    final cardColor = Color.lerp(
      scheme.surface,
      scheme.surfaceContainerHighest,
      isDark ? 0.35 : 0.22,
    )!;
    final shadowColor = isDark ? Colors.black : Colors.black;
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 720,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: bgColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShareHeader(
              title: title,
              count: messages.length,
              scheme: scheme,
              mutedColor: mutedColor,
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withValues(alpha: isDark ? 0.22 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < messages.length; i++) ...[
                    _ShareMessageBubble(message: messages[i], scheme: scheme),
                    if (i != messages.length - 1) const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              pageNumber == null || pageCount == null
                  ? 'Shared from LynAI'
                  : 'Shared from LynAI · $pageNumber/$pageCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mutedColor,
                fontSize: 18,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ShareHeader extends StatelessWidget {
  final String title;
  final int count;
  final ColorScheme scheme;
  final Color mutedColor;

  const _ShareHeader({
    required this.title,
    required this.count,
    required this.scheme,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.isEmpty ? 'LynAI 对话' : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$count 条精选消息 · ${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}',
                style: TextStyle(color: mutedColor, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ShareMessageBubble extends StatelessWidget {
  final Message message;
  final ColorScheme scheme;

  const _ShareMessageBubble({required this.message, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final bubbleColor = isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final textColor = isUser ? scheme.onPrimaryContainer : scheme.onSurface;
    final labelColor = scheme.onSurfaceVariant;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isUser ? 'You' : 'LynAI',
            style: TextStyle(
              color: labelColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(22),
                topRight: const Radius.circular(22),
                bottomLeft: Radius.circular(isUser ? 22 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.content.trim().isNotEmpty)
                  MarkdownWithLatex(
                    content: message.content.trim(),
                    selectable: false,
                    wrapCodeBlocks: true,
                    textStyle: TextStyle(
                      fontSize: 20,
                      height: 1.45,
                      color: textColor,
                    ),
                  ),
                if (message.images.isNotEmpty &&
                    message.content.trim().isNotEmpty)
                  const SizedBox(height: 12),
                if (message.images.isNotEmpty)
                  _ShareImageStrip(images: message.images),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareImageStrip extends StatelessWidget {
  final List<MessageImage> images;

  const _ShareImageStrip({required this.images});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: images.map((image) {
        final file = File(image.path);
        if (!file.existsSync()) return const SizedBox.shrink();
        if (!image.isImage) {
          return Container(
            width: 220,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    image.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(file, width: 150, height: 150, fit: BoxFit.cover),
        );
      }).toList(),
    );
  }
}

class _DialogSettingsContent extends StatefulWidget {
  final ConversationSettings settings;
  final ValueChanged<ConversationSettings> onChanged;

  const _DialogSettingsContent({
    required this.settings,
    required this.onChanged,
  });

  @override
  State<_DialogSettingsContent> createState() => _DialogSettingsContentState();
}

class _DialogSettingsContentState extends State<_DialogSettingsContent> {
  bool _showSpeechList = false;
  bool _showImageList = false;
  bool _showImageRecognitionList = false;
  bool _showRoleList = false;
  bool _showSystemPromptList = false;
  String? _expandedSpeechId;
  String? _expandedImageId;
  String? _expandedImageRecognitionId;
  late ConversationSettings _settings;

  @override
  void initState() {
    super.initState();
    _settings = widget.settings;
  }

  void _updateSettings(ConversationSettings settings) {
    _settings = settings;
    widget.onChanged(settings);
  }

  @override
  Widget build(BuildContext context) {
    final set = context.watch<SettingsProvider>().settings;
    final mp = context.watch<ModelConfigProvider>();
    final speechModel = _settings.speechModelId != null
        ? _findModelConfigById(mp.models, _settings.speechModelId!)
        : null;
    final ocrModel = _settings.imageModelId != null
        ? _findModelConfigById(mp.models, _settings.imageModelId!)
        : null;
    final imageRecognitionModel = _settings.imageRecognitionModelId != null
        ? _findModelConfigById(mp.models, _settings.imageRecognitionModelId!)
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.35,
      maxChildSize: 0.85,
      expand: false,
      builder: (ctx, scrollCtrl) => SingleChildScrollView(
        controller: scrollCtrl,
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.tune, size: 22),
                  const SizedBox(width: 8),
                  Text('对话设置', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 20),
              Text(
                '角色管理',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(() => _showRoleList = !_showRoleList),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _showRoleList
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _showRoleList
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.05)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          context.watch<SettingsProvider>().currentRole.name,
                        ),
                      ),
                      Icon(
                        _showRoleList ? Icons.expand_less : Icons.expand_more,
                        size: 18,
                      ),
                    ],
                  ),
                ),
              ),
              if (_showRoleList) ...[const SizedBox(height: 4), _roleList(set)],
              const SizedBox(height: 20),
              // 系统提示词
              Text(
                '系统提示词',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () => setState(
                  () => _showSystemPromptList = !_showSystemPromptList,
                ),
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: _showSystemPromptList
                          ? Theme.of(
                              context,
                            ).colorScheme.primary.withValues(alpha: 0.3)
                          : Colors.grey.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                    color: _showSystemPromptList
                        ? Theme.of(
                            context,
                          ).colorScheme.primary.withValues(alpha: 0.05)
                        : null,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _currentSystemPromptLabel(set),
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey[600],
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      Icon(
                        _showSystemPromptList
                            ? Icons.expand_less
                            : Icons.expand_more,
                        size: 18,
                        color: Colors.grey[400],
                      ),
                    ],
                  ),
                ),
              ),
              if (_showSystemPromptList) ...[
                const SizedBox(height: 4),
                _systemPromptList(set),
              ],
              const SizedBox(height: 20),
              // 语音转文字模型
              Text(
                '语音转文字模型',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              _inlineModelPicker(
                mp: mp,
                category: ModelConfig.categorySpeech,
                currentModel: speechModel,
                showList: _showSpeechList,
                expandedId: _expandedSpeechId,
                hint: '未设置（设置后将支持发送语音）',
                icon: Icons.mic,
                onToggle: () => setState(() {
                  _showSpeechList = !_showSpeechList;
                  _showImageList = false;
                  _expandedSpeechId = null;
                }),
                onSelect: (id) {
                  _updateSettings(_settings.copyWith(speechModelId: id));
                  setState(() {
                    _showSpeechList = false;
                    _expandedSpeechId = null;
                  });
                },
                onExpandProvider: (id) {
                  _updateSettings(_settings.copyWith(speechModelId: id));
                  setState(() {
                    _expandedSpeechId = id;
                  });
                },
                onSelectSub: (config, modelName) {
                  final c = config.copyWith(modelName: modelName);
                  context.read<ModelConfigProvider>().updateModel(c);
                  setState(() {
                    _showSpeechList = false;
                    _expandedSpeechId = null;
                  });
                },
                onClear: () {
                  _updateSettings(_settings.copyWith(speechModelId: null));
                  setState(() {
                    _expandedSpeechId = null;
                  });
                },
              ),
              const SizedBox(height: 20),
              // OCR 模型
              Text(
                'OCR 模型',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              _inlineModelPicker(
                mp: mp,
                category: ModelConfig.categoryOcr,
                currentModel: ocrModel,
                showList: _showImageList,
                expandedId: _expandedImageId,
                hint: '未设置（非图片文件将跳过 OCR，仅保留附件信息）',
                icon: Icons.image,
                onToggle: () => setState(() {
                  _showImageList = !_showImageList;
                  _showSpeechList = false;
                  _expandedImageId = null;
                }),
                onSelect: (id) {
                  _updateSettings(_settings.copyWith(imageModelId: id));
                  setState(() {
                    _showImageList = false;
                    _expandedImageId = null;
                  });
                },
                onExpandProvider: (id) {
                  _updateSettings(_settings.copyWith(imageModelId: id));
                  setState(() {
                    _expandedImageId = id;
                  });
                },
                onSelectSub: (config, modelName) {
                  final c = config.copyWith(modelName: modelName);
                  context.read<ModelConfigProvider>().updateModel(c);
                  setState(() {
                    _showImageList = false;
                    _expandedImageId = null;
                  });
                },
                onClear: () {
                  _updateSettings(_settings.copyWith(imageModelId: null));
                  setState(() {
                    _expandedImageId = null;
                  });
                },
              ),
              const SizedBox(height: 16),
              // 文件识别模型
              Text(
                '文件识别模型',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              _inlineModelPicker(
                mp: mp,
                category: ModelConfig.categoryChat,
                currentModel: imageRecognitionModel,
                showList: _showImageRecognitionList,
                expandedId: _expandedImageRecognitionId,
                hint: '未设置（启用文件识别后将用该模型读取附件）',
                icon: Icons.file_present_outlined,
                onToggle: () => setState(() {
                  _showSpeechList = false;
                  _showImageList = false;
                  _showSystemPromptList = false;
                  _showImageRecognitionList = !_showImageRecognitionList;
                  _expandedImageRecognitionId = null;
                }),
                onSelect: (id) {
                  _updateSettings(
                    _settings.copyWith(imageRecognitionModelId: id),
                  );
                  setState(() {
                    _showImageRecognitionList = false;
                    _expandedImageRecognitionId = null;
                  });
                },
                onExpandProvider: (id) {
                  _updateSettings(
                    _settings.copyWith(imageRecognitionModelId: id),
                  );
                  setState(() => _expandedImageRecognitionId = id);
                },
                onSelectSub: (config, modelName) {
                  final c = config.copyWith(modelName: modelName);
                  context.read<ModelConfigProvider>().updateModel(c);
                },
                onClear: () {
                  _updateSettings(
                    _settings.copyWith(imageRecognitionModelId: null),
                  );
                },
                filter: (config) => config.models.any(
                  (entry) => entry.enabled && entry.supportsVision,
                ),
                entryFilter: (entry) => entry.supportsVision,
              ),
              const SizedBox(height: 16),
              // 文件识别提示词
              Text(
                '文件识别提示词',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              InkWell(
                onTap: () async {
                  final result = await _showPromptDialog(
                    context,
                    _settings.imageRecognitionPrompt,
                  );
                  if (result != null && mounted) {
                    _updateSettings(
                      _settings.copyWith(imageRecognitionPrompt: result),
                    );
                  }
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Colors.grey.withValues(alpha: 0.3),
                    ),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _settings.imageRecognitionPrompt,
                    style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                  ),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('完成'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _inlineModelPicker({
    required ModelConfigProvider mp,
    required String category,
    required ModelConfig? currentModel,
    required bool showList,
    required String? expandedId,
    required String hint,
    required IconData icon,
    required VoidCallback onToggle,
    required void Function(String) onSelect,
    required void Function(String) onExpandProvider,
    required void Function(ModelConfig, String) onSelectSub,
    required VoidCallback onClear,
    bool Function(ModelConfig)? filter,
    bool Function(ModelEntry)? entryFilter,
  }) {
    final compact = MediaQuery.sizeOf(context).width < 380;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (currentModel != null)
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: Theme.of(
                context,
              ).colorScheme.primary.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: Theme.of(
                  context,
                ).colorScheme.primary.withValues(alpha: 0.2),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  icon,
                  size: 14,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    compact
                        ? currentModel.name
                        : '${currentModel.name} / ${currentModel.modelName}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: onClear,
                  child: Icon(
                    Icons.close,
                    size: 14,
                    color: Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ),
        InkWell(
          onTap: onToggle,
          borderRadius: BorderRadius.circular(8),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(8),
              border: Border.all(
                color: showList
                    ? Theme.of(
                        context,
                      ).colorScheme.primary.withValues(alpha: 0.3)
                    : Colors.grey.withValues(alpha: 0.3),
              ),
              color: showList
                  ? Theme.of(
                      context,
                    ).colorScheme.primary.withValues(alpha: 0.05)
                  : null,
            ),
            child: Row(
              children: [
                Icon(
                  icon,
                  size: 18,
                  color: showList
                      ? Theme.of(context).colorScheme.primary
                      : (currentModel != null
                            ? Theme.of(context).colorScheme.primary
                            : Colors.grey[400]),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    currentModel != null ? '已选择：${currentModel.name}' : hint,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: 13,
                      color: currentModel != null ? null : Colors.grey[500],
                    ),
                  ),
                ),
                Icon(
                  showList ? Icons.expand_less : Icons.expand_more,
                  size: 18,
                  color: Colors.grey[400],
                ),
              ],
            ),
          ),
        ),
        if (showList) ...[
          const SizedBox(height: 4),
          _modelSelectList(
            mp,
            category,
            onSelect,
            onSelectSub,
            currentModel?.id,
            expandedId,
            (id) {
              if (id == expandedId) {
                onToggle();
              } else {
                onExpandProvider(id);
              }
            },
            filter,
            entryFilter,
          ),
        ],
      ],
    );
  }

  Widget _modelSelectList(
    ModelConfigProvider mp,
    String category,
    void Function(String) onSelect,
    void Function(ModelConfig, String) onSelectSub,
    String? selectedId,
    String? expandedId,
    void Function(String) onExpandToggle,
    bool Function(ModelConfig)? filter,
    bool Function(ModelEntry)? entryFilter,
  ) {
    final models = mp
        .modelsByCategory(category)
        .where((model) {
          return filter == null || filter(model);
        })
        .toList(growable: false);
    return Container(
      constraints: const BoxConstraints(maxHeight: 300),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: models.length,
        itemBuilder: (_, i) {
          final m = models[i];
          final isSelected = selectedId != null && m.id == selectedId;
          final isExpanded = expandedId != null && m.id == expandedId;
          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                dense: true,
                title: Text(
                  m.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(fontSize: 14),
                ),
                subtitle: Text(
                  m.hasMultipleModels
                      ? '${m.enabledModelNames.length} 个模型'
                      : m.modelName,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 11, color: Colors.grey[500]),
                ),
                leading: Icon(
                  isSelected ? Icons.check_circle : Icons.circle_outlined,
                  size: 18,
                  color: isSelected
                      ? Theme.of(context).colorScheme.primary
                      : Colors.grey[400],
                ),
                trailing: m.hasMultipleModels
                    ? const Icon(Icons.chevron_right, size: 16)
                    : null,
                onTap: () {
                  if (m.hasMultipleModels) {
                    onExpandToggle(m.id);
                  } else {
                    onSelect(m.id);
                  }
                },
              ),
              if (isExpanded && m.hasMultipleModels)
                ...m.models
                    .where((e) => e.enabled)
                    .where((e) => entryFilter == null || entryFilter(e))
                    .map(
                      (e) => ListTile(
                        dense: true,
                        contentPadding: const EdgeInsets.only(left: 56),
                        leading: Icon(
                          e.name == m.modelName
                              ? Icons.radio_button_checked
                              : Icons.radio_button_off,
                          size: 14,
                          color: e.name == m.modelName
                              ? Theme.of(context).colorScheme.primary
                              : Colors.grey,
                        ),
                        title: Text(
                          e.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontSize: 13,
                            fontFamily: 'monospace',
                          ),
                        ),
                        onTap: () => onSelectSub(m, e.name),
                      ),
                    ),
            ],
          );
        },
      ),
    );
  }

  Future<String?> _showPromptDialog(BuildContext context, String current) {
    final ctrl = TextEditingController(text: current);
    return showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('自定义提示词'),
        content: TextField(
          controller: ctrl,
          maxLines: 3,
          decoration: const InputDecoration(
            border: OutlineInputBorder(),
            hintText: '请根据下面的文件内容或识别结果回答。',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              final text = ctrl.text.trim();
              Navigator.pop(ctx, text);
            },
            child: const Text('保存'),
          ),
        ],
      ),
    );
  }

  String _currentSystemPromptLabel(AppSettings set) {
    if (_settings.selectedSystemPromptId != null) {
      try {
        final p = set.systemPrompts.firstWhere(
          (p) => p.id == _settings.selectedSystemPromptId,
        );
        return p.title;
      } catch (_) {}
    }
    return '默认';
  }

  void _closeSystemPromptList() {
    setState(() => _showSystemPromptList = false);
  }

  Widget _systemPromptList(AppSettings set) {
    final prompts = set.systemPrompts;
    final selectedId = _settings.selectedSystemPromptId;
    return Container(
      constraints: const BoxConstraints(maxHeight: 220),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.builder(
        key: ValueKey('sysprompt_${selectedId ?? 'none'}_${prompts.length}'),
        shrinkWrap: true,
        itemCount: 1 + prompts.length + 1,
        itemBuilder: (_, i) {
          if (i == 0) {
            final sel = selectedId == null;
            return ListTile(
              dense: true,
              leading: Icon(
                sel ? Icons.check_circle : Icons.circle_outlined,
                size: 18,
                color: sel
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey,
              ),
              title: const Text('默认', style: TextStyle(fontSize: 14)),
              subtitle: const Text(
                'You are a helpful assistant.',
                style: TextStyle(fontSize: 11),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              onTap: () {
                _updateSettings(
                  _settings.copyWith(selectedSystemPromptId: null),
                );
                _closeSystemPromptList();
              },
            );
          }
          if (i == 1 + prompts.length) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.add,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    '添加系统提示词',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  onTap: () => _addSystemPrompt(),
                ),
              ],
            );
          }
          final p = prompts[i - 1];
          final sel = p.id == selectedId;
          return ListTile(
            dense: true,
            leading: Icon(
              sel ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: sel ? Theme.of(context).colorScheme.primary : Colors.grey,
            ),
            title: Text(p.title, style: const TextStyle(fontSize: 14)),
            subtitle: Text(
              p.content.length > 40
                  ? '${p.content.substring(0, 40)}...'
                  : p.content,
              style: const TextStyle(fontSize: 11),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              icon: const Icon(Icons.edit, size: 18),
              onPressed: () => _editSystemPrompt(p),
            ),
            onTap: () {
              _updateSettings(_settings.copyWith(selectedSystemPromptId: p.id));
              _closeSystemPromptList();
            },
          );
        },
      ),
    );
  }

  Widget _roleList(AppSettings set) {
    final roles = set.roles;
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: roles.length + 1,
        itemBuilder: (_, i) {
          if (i == roles.length) {
            return Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Divider(height: 1),
                ListTile(
                  dense: true,
                  leading: Icon(
                    Icons.add,
                    size: 18,
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  title: Text(
                    '添加角色',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.primary,
                    ),
                  ),
                  onTap: _addRole,
                ),
              ],
            );
          }
          final role = roles[i];
          final selected = role.id == set.currentRoleId;
          return ListTile(
            dense: true,
            leading: Icon(
              selected ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: selected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            title: Text(role.name),
            subtitle: Text(
              role.description.isNotEmpty
                  ? role.description
                  : role.systemPrompt,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: role.id == ChatRole.defaultId
                ? null
                : IconButton(
                    icon: const Icon(Icons.edit, size: 18),
                    onPressed: () => _editRole(role),
                  ),
            onTap: () {
              context.read<SettingsProvider>().selectRole(role.id);
              _updateSettings(_roleConversationSettings(role));
              setState(() => _showRoleList = false);
            },
          );
        },
      ),
    );
  }

  ConversationSettings _roleConversationSettings(ChatRole role) {
    return _settings.copyWith(
      modelId: role.modelId ?? _settings.modelId,
      selectedSystemPromptId: role.id == ChatRole.defaultId ? null : role.id,
      systemPrompt: role.systemPrompt,
    );
  }

  void _addRole() {
    showDialog(
      context: context,
      builder: (ctx) => _RoleEditDialog(
        onSave: (name, description, prompt, modelId, themeColor) {
          context.read<SettingsProvider>().addRole(
            name: name,
            description: description,
            systemPrompt: prompt,
            modelId: modelId,
            themeColor: themeColor,
          );
        },
      ),
    );
  }

  void _editRole(ChatRole role) {
    final sp = context.read<SettingsProvider>();
    showDialog(
      context: context,
      builder: (ctx) => _RoleEditDialog(
        initialRole: role,
        onSave: (name, description, prompt, modelId, themeColor) {
          sp.updateRole(
            id: role.id,
            name: name,
            description: description,
            systemPrompt: prompt,
            modelId: modelId,
            themeColor: themeColor,
          );
          if (role.id == sp.settings.currentRoleId) {
            _updateSettings(_roleConversationSettings(sp.currentRole));
          }
        },
        onDelete: () => sp.deleteRole(role.id),
      ),
    );
  }

  void _addSystemPrompt() {
    showDialog(
      context: context,
      builder: (ctx) => _SystemPromptEditDialog(
        onSave: (title, content) {
          final id = context.read<SettingsProvider>().addSystemPrompt(
            title,
            content,
          );
          _updateSettings(_settings.copyWith(selectedSystemPromptId: id));
        },
      ),
    );
  }

  void _editSystemPrompt(SystemPrompt p) {
    final sp = context.read<SettingsProvider>();
    showDialog(
      context: context,
      builder: (ctx) => _SystemPromptEditDialog(
        initialTitle: p.title,
        initialContent: p.content,
        onSave: (title, content) {
          sp.updateSystemPrompt(p.id, title, content);
        },
        onDelete: () {
          sp.deleteSystemPrompt(p.id);
        },
      ),
    );
  }
}

class _SystemPromptEditDialog extends StatefulWidget {
  final String initialTitle;
  final String initialContent;
  final void Function(String title, String content) onSave;
  final VoidCallback? onDelete;

  const _SystemPromptEditDialog({
    this.initialTitle = '',
    this.initialContent = '',
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_SystemPromptEditDialog> createState() =>
      _SystemPromptEditDialogState();
}

class _RoleEditDialog extends StatefulWidget {
  final ChatRole? initialRole;
  final void Function(
    String name,
    String description,
    String systemPrompt,
    String? modelId,
    Color? themeColor,
  )
  onSave;
  final VoidCallback? onDelete;

  const _RoleEditDialog({
    this.initialRole,
    required this.onSave,
    this.onDelete,
  });

  @override
  State<_RoleEditDialog> createState() => _RoleEditDialogState();
}

class _RoleEditDialogState extends State<_RoleEditDialog> {
  late final _nameCtrl = TextEditingController(
    text: widget.initialRole?.name ?? '',
  );
  late final _descCtrl = TextEditingController(
    text: widget.initialRole?.description ?? '',
  );
  late final _promptCtrl = TextEditingController(
    text: widget.initialRole?.systemPrompt ?? '',
  );
  late String? _modelId = widget.initialRole?.modelId;
  late Color? _themeColor = widget.initialRole?.themeColor;

  static const _colors = [
    Colors.blue,
    Colors.green,
    Colors.orange,
    Colors.purple,
    Colors.red,
    Colors.teal,
    Colors.indigo,
    Colors.pink,
    Color(0xFF6C5CE7),
    Color(0xFF00B894),
    Color(0xFFE17055),
    Color(0xFF355C7D),
  ];

  @override
  void dispose() {
    _nameCtrl.dispose();
    _descCtrl.dispose();
    _promptCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelConfigProvider>().modelsByCategory(
      ModelConfig.categoryChat,
    );
    return AlertDialog(
      title: Text(widget.initialRole == null ? '添加角色' : '编辑角色'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: '角色名称',
                border: OutlineInputBorder(),
                hintText: '默认',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _descCtrl,
              minLines: 2,
              maxLines: 4,
              decoration: const InputDecoration(
                labelText: '描述',
                border: OutlineInputBorder(),
                hintText: '这个角色的用途或风格',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _promptCtrl,
              minLines: 3,
              maxLines: 8,
              decoration: const InputDecoration(
                labelText: '系统提示词',
                border: OutlineInputBorder(),
                hintText: 'You are a helpful assistant.',
                alignLabelWithHint: true,
              ),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String?>(
              initialValue: _modelId,
              decoration: const InputDecoration(
                labelText: '模型（可选）',
                border: OutlineInputBorder(),
              ),
              isExpanded: true,
              items: [
                const DropdownMenuItem<String?>(
                  value: null,
                  child: Text('不指定'),
                ),
                ...models.map(
                  (m) => DropdownMenuItem<String?>(
                    value: m.id,
                    child: Text('${m.name} / ${m.modelName}'),
                  ),
                ),
              ],
              onChanged: (v) => setState(() => _modelId = v),
            ),
            const SizedBox(height: 14),
            Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '主题配色（可选）',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ),
            const SizedBox(height: 8),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.grey.withValues(alpha: 0.35)),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  ChoiceChip(
                    label: const Text('无'),
                    selected: _themeColor == null,
                    onSelected: (_) => setState(() => _themeColor = null),
                  ),
                  for (final color in _colors)
                    Tooltip(
                      message:
                          '#${color.toARGB32().toRadixString(16).padLeft(8, '0').substring(2).toUpperCase()}',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16),
                        onTap: () => setState(() => _themeColor = color),
                        child: Container(
                          width: 32,
                          height: 32,
                          decoration: BoxDecoration(
                            color: color,
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: _themeColor?.toARGB32() == color.toARGB32()
                                  ? Theme.of(context).colorScheme.onSurface
                                  : Colors.transparent,
                              width: 2,
                            ),
                            boxShadow: [
                              BoxShadow(
                                color: color.withValues(alpha: 0.25),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final name = _nameCtrl.text.trim();
            final description = _descCtrl.text.trim();
            final prompt = _promptCtrl.text.trim();
            if (name.isEmpty || prompt.isEmpty) return;
            Navigator.pop(context);
            widget.onSave(name, description, prompt, _modelId, _themeColor);
          },
          child: const Text('保存'),
        ),
        if (widget.onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete!();
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
      ],
    );
  }
}

class _SystemPromptEditDialogState extends State<_SystemPromptEditDialog> {
  late final _titleCtrl = TextEditingController(text: widget.initialTitle);
  late final _contentCtrl = TextEditingController(text: widget.initialContent);

  @override
  void dispose() {
    _titleCtrl.dispose();
    _contentCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.onDelete != null ? '编辑系统提示词' : '添加系统提示词'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _titleCtrl,
            decoration: const InputDecoration(
              labelText: '标题',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _contentCtrl,
            maxLines: 8,
            minLines: 3,
            decoration: const InputDecoration(
              labelText: '系统提示词',
              border: OutlineInputBorder(),
              hintText: 'You are a helpful assistant.',
              alignLabelWithHint: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('取消'),
        ),
        TextButton(
          onPressed: () {
            final title = _titleCtrl.text.trim();
            final content = _contentCtrl.text.trim();
            if (title.isEmpty || content.isEmpty) return;
            Navigator.pop(context);
            widget.onSave(title, content);
          },
          child: const Text('保存'),
        ),
        if (widget.onDelete != null)
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              widget.onDelete!();
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
      ],
    );
  }
}

class _HistoryDrawer extends StatefulWidget {
  final void Function(String) onSelect;
  final String? currentConvId;
  const _HistoryDrawer({required this.onSelect, this.currentConvId});

  @override
  State<_HistoryDrawer> createState() => _HistoryDrawerState();
}

class _HistoryDrawerState extends State<_HistoryDrawer> {
  final _searchCtrl = TextEditingController();
  String _q = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final p = context.watch<ConversationProvider>();
    final sp = context.watch<SettingsProvider>();
    final results = p.searchConversations(_q);
    final roles = sp.settings.roles;
    final currentRoleId = sp.settings.currentRoleId;
    final currentRole = roles.firstWhere(
      (role) => role.id == currentRoleId,
      orElse: ChatRole.defaultRole,
    );
    final currentResults = results
        .where(
          (r) => (r['conversation'] as Conversation).roleId == currentRoleId,
        )
        .toList();
    final otherResults = results
        .where(
          (r) => (r['conversation'] as Conversation).roleId != currentRoleId,
        )
        .toList();
    final otherRoleIds = otherResults
        .map((r) => (r['conversation'] as Conversation).roleId)
        .toSet()
        .toList();
    return Column(
      children: [
        Container(
          width: double.infinity,
          padding: EdgeInsets.only(
            top: MediaQuery.of(context).padding.top + 16,
            left: 16,
            right: 16,
            bottom: 12,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.history),
                  const SizedBox(width: 8),
                  Text('历史对话', style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchCtrl,
                decoration: InputDecoration(
                  hintText: '搜索历史...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _q.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchCtrl.clear();
                            setState(() => _q = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(
                    context,
                  ).colorScheme.surface.withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 8,
                  ),
                ),
                onChanged: (v) => setState(() => _q = v),
              ),
            ],
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    _q.isEmpty ? '暂无历史对话' : '无匹配结果',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView(
                  children: [
                    _roleHeader(
                      context,
                      currentRole.name,
                      currentRole.themeColor,
                    ),
                    if (currentResults.isEmpty)
                      ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(_q.isEmpty ? '当前角色暂无对话' : '未找到匹配的对话'),
                      ),
                    for (final result in currentResults)
                      _conversationTile(
                        context,
                        result['conversation'] as Conversation,
                        currentRole.themeColor,
                      ),
                    for (final roleId in otherRoleIds) ...[
                      Builder(
                        builder: (context) {
                          final role = roles.firstWhere(
                            (role) => role.id == roleId,
                            orElse: () =>
                                ChatRole.defaultRole().copyWith(name: roleId),
                          );
                          final list = otherResults
                              .where(
                                (r) =>
                                    (r['conversation'] as Conversation)
                                        .roleId ==
                                    roleId,
                              )
                              .toList();
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              InkWell(
                                onTap: () => sp.selectRole(role.id),
                                child: _roleHeader(
                                  context,
                                  role.name,
                                  role.themeColor,
                                ),
                              ),
                              for (final result in list)
                                _conversationTile(
                                  context,
                                  result['conversation'] as Conversation,
                                  role.themeColor,
                                ),
                            ],
                          );
                        },
                      ),
                    ],
                  ],
                ),
        ),
      ],
    );
  }

  Widget _roleHeader(BuildContext context, String name, Color? color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        name,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: color ?? Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _conversationTile(
    BuildContext context,
    Conversation c,
    Color? roleColor,
  ) {
    final active = c.id == widget.currentConvId;
    return ListTile(
      selected: active,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      leading: Icon(Icons.chat, size: 20, color: roleColor),
      title: Text(
        c.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          fontWeight: active ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        c.preview,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(fontSize: 12),
      ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () => _deleteDialog(context, c),
      ),
      onLongPress: () => _deleteDialog(context, c),
      onTap: () {
        context.read<SettingsProvider>().selectRole(c.roleId);
        widget.onSelect(c.id);
      },
    );
  }

  void _deleteDialog(BuildContext context, Conversation c) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定要删除"${c.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              context.read<ConversationProvider>().deleteConversation(c.id);
              Navigator.pop(ctx);
              if (c.id == widget.currentConvId) widget.onSelect('');
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
        ],
      ),
    );
  }
}
