import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
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
import 'package:url_launcher/url_launcher.dart';
import '../models/agent_plan.dart';
import '../models/agent_runtime.dart';
import '../models/agent_user_interaction.dart';
import '../models/agent_trace.dart';
import '../models/conversation.dart';
import '../models/chat_role.dart';
import '../models/composer_reference.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../providers/conversation_provider.dart';
import '../providers/feature_provider.dart';
import '../providers/calendar_provider.dart';
import '../providers/knowledge_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/mcp_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/task_provider.dart';
import '../services/attachment_storage_service.dart';
import '../services/api_message_builder.dart';
import '../services/api_service.dart';
import '../services/composer_selector_registry.dart';
import '../services/agent_loop_runtime.dart';
import '../services/agent_persistence_lifecycle.dart';
import '../services/agent_tool_registry.dart';
import '../services/agent_tool_result_sanitizer.dart';
import '../services/agent_tool_execution_service.dart';
import '../services/agent_user_interaction_broker.dart';
import '../services/backend_client.dart';
import '../services/plugin_lua_runtime_service.dart';
import '../services/knowledge_annotation_prompt.dart';
import '../services/generation_background_service.dart';
import '../services/model_recognition_service.dart';
import '../services/storage_v2_service.dart';
import '../services/system_scroll_capture_service.dart';
import '../services/tool_call_service.dart';
import '../services/stream_chunk_agent_adapter.dart';
import '../services/web_search_service.dart';
import '../utils/file_picker_io_utils.dart';
import '../utils/chat_search_matcher.dart';
import '../utils/share_image_utils.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/latex_renderer.dart';
import '../widgets/ai_explain_selection_area.dart';
import '../widgets/chat_composer_keyboard.dart';
import '../widgets/knowledge_explanation_dialog.dart';
import '../widgets/reference_composer.dart';
import 'chat/chat_image_exporter.dart';
import 'chat/command_palette.dart';
import 'chat/dialog_settings_content.dart';
import 'chat/history_drawer.dart';
import 'chat/share_conversation_image.dart';

final class _UserTextHighlight {
  const _UserTextHighlight({
    required this.start,
    required this.end,
    required this.current,
  });

  final int start;
  final int end;
  final bool current;
}

class _LinkAwareSelectableText extends StatefulWidget {
  const _LinkAwareSelectableText({
    required this.content,
    required this.onOpenLink,
    required this.onExplainSelection,
    this.highlights = const [],
  });

  final String content;
  final List<_UserTextHighlight> highlights;
  final ValueChanged<String> onOpenLink;
  final AiExplainSelectionCallback onExplainSelection;

  @override
  State<_LinkAwareSelectableText> createState() =>
      _LinkAwareSelectableTextState();
}

class _LinkAwareSelectableTextState extends State<_LinkAwareSelectableText> {
  static final _urlPattern = RegExp(r'https?://[^\s<>]+', caseSensitive: false);
  final List<TapGestureRecognizer> _recognizers = [];

  @override
  void dispose() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
    final boundaries = <int>{0, widget.content.length};
    final urls = _urlPattern.allMatches(widget.content).toList();
    for (final match in urls) {
      boundaries
        ..add(match.start)
        ..add(match.end);
    }
    for (final highlight in widget.highlights) {
      boundaries
        ..add(highlight.start)
        ..add(highlight.end);
    }
    final points = boundaries.toList()..sort();
    final scheme = Theme.of(context).colorScheme;
    final spans = <TextSpan>[];
    for (var index = 0; index < points.length - 1; index++) {
      final start = points[index];
      final end = points[index + 1];
      if (start == end) continue;
      final url = urls.cast<RegExpMatch?>().firstWhere(
        (match) => match != null && start >= match.start && end <= match.end,
        orElse: () => null,
      );
      final highlight = widget.highlights
          .cast<_UserTextHighlight?>()
          .firstWhere(
            (item) => item != null && start >= item.start && end <= item.end,
            orElse: () => null,
          );
      TapGestureRecognizer? recognizer;
      if (url != null) {
        final href = url.group(0)!;
        recognizer = TapGestureRecognizer()
          ..onTap = () => widget.onOpenLink(href);
        _recognizers.add(recognizer);
      }
      spans.add(
        TextSpan(
          text: widget.content.substring(start, end),
          recognizer: recognizer,
          style: TextStyle(
            color: highlight?.current == true
                ? scheme.onPrimary
                : url != null
                ? scheme.primary
                : highlight != null
                ? Colors.black
                : null,
            backgroundColor: highlight?.current == true
                ? scheme.primary
                : highlight != null
                ? Colors.yellow
                : null,
            fontWeight: highlight?.current == true
                ? FontWeight.w700
                : highlight != null
                ? FontWeight.w600
                : null,
            decoration: url != null ? TextDecoration.underline : null,
          ),
        ),
      );
    }
    return AiExplainSelectionArea(
      onExplain: widget.onExplainSelection,
      child: Text.rich(
        TextSpan(style: const TextStyle(fontSize: 15), children: spans),
      ),
    );
  }
}

/// 重试历史条目。
///
/// 记录一次对话生成中用户的输入和助手回复 ID，用于错误重试分支。
class _RetryEntry {
  String userContent;
  List<MessageImage> userImages;
  String? assistantId;
  String? assistantContent;
  List<MessageImage> assistantImages = const [];
  String? thinkingContent;
  _RetryEntry(this.userContent, [this.userImages = const []]);

  bool get hasAssistantSnapshot =>
      (assistantContent?.isNotEmpty ?? false) || assistantImages.isNotEmpty;
}

/// 待发送图片的数据模型。
///
/// 存储图片本地路径、文件名、大小和 MIME 类型，可转换为 [MessageImage]。
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

/// 流式响应草稿状态。
///
/// 封装流式输出期间的正文、思维链和当前阶段标识。
class _StreamDraft {
  final String content;
  final String? thinking;
  final String? status;
  final String? activeToolName;
  final String? activeSkillDisplayName;

  const _StreamDraft({
    this.content = '',
    this.thinking,
    this.status,
    this.activeToolName,
    this.activeSkillDisplayName,
  });
}

class _ChatSearchMatch {
  final String messageId;
  final int messageIndex;
  final int start;
  final int end;

  const _ChatSearchMatch({
    required this.messageId,
    required this.messageIndex,
    required this.start,
    required this.end,
  });
}

enum _PreviewImageAction { save, copyImage, share, close }

/// 主对话页面。
///
/// 负责输入、附件、语音、流式请求、工具调用、重试分支和对话分享。实际数据
/// 写入 [ConversationProvider]，外部 API 协议交给 [ApiService]。
class ChatPage extends StatefulWidget {
  final String? conversationId;
  final ApiService? api;
  final bool active;
  final VoidCallback? onConversationLoaded;
  final void Function(bool Function() handler)? onBackHandlerChanged;
  final ValueChanged<bool>? onBackAvailabilityChanged;
  final void Function(VoidCallback handler)? onNewConversationHandlerChanged;
  const ChatPage({
    super.key,
    this.conversationId,
    this.api,
    this.active = true,
    this.onConversationLoaded,
    this.onBackHandlerChanged,
    this.onBackAvailabilityChanged,
    this.onNewConversationHandlerChanged,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

/// 对话页状态管理。
///
/// 维护消息列表滚动、流式输出、语音输入/识别、图片识别、工具调用、
/// 撤回/重试、分享导出和会话设置等全部交互状态。
class _ChatPageState extends State<ChatPage> with WidgetsBindingObserver {
  static const _nativeToolsChannel = MethodChannel('lynai/native_tools');
  static const _emptyAssistantReply = '模型没有返回内容，请稍后重试或检查模型配置。';
  static const _streamWaitTimeout = Duration(minutes: 5);

  final _msgCtrl = ReferenceComposerController();
  final _searchCtrl = TextEditingController();
  final _scrollCtrl = ScrollController();
  late final ScrollController _historyScrollController;
  final _focusNode = FocusNode();
  final _searchFocusNode = FocusNode();
  final _audioRecorder = AudioRecorder();
  final _generationBackgroundService = const GenerationBackgroundService();
  late final AttachmentStorageService _attachmentStorage;
  late final ApiService _api;
  late final bool _ownsApi;
  late final ModelRecognitionService _recognition;
  final _streamDraft = ValueNotifier<_StreamDraft>(const _StreamDraft());
  final _inputRevision = ValueNotifier<int>(0);

  String? _convId;
  String? _pendingModelId;
  bool _thinking = true;
  bool _agentEnabled = false;
  ConversationSettings? _draftSettings;
  bool _streaming = false;
  bool _preparingSend = false;
  bool _showAttach = false;
  bool _showModelMenu = false;
  bool _showCommandPalette = false;
  int _refSeq = 0;
  bool _recording = false;
  bool _transcribingSpeech = false;
  bool _autoScrollToBottom = true;
  bool _showScrollToBottom = false;
  bool _scrollEndScheduled = false;
  double _lastBottomInset = 0;
  bool _keyboardLiftRequestedByInputTap = false;
  bool _keyboardShouldLiftMessages = false;
  DateTime? _lastAutoScrollAt;
  int _scrollGen = 0;
  String? _thinkingTxt;
  bool _thinkExpanded = false;
  final Map<String, String?> _thinkMap = {};
  final Set<String> _expandedThinkIds = {};
  final List<_PendingImage> _pendingImages = [];
  bool _showImageRecognitionList = false;
  bool _showImageGenerationList = false;
  bool _shareSelecting = false;
  bool _sharingImage = false;
  bool _showSearch = false;
  bool? _agentPlanExpanded;
  final Set<String> _selectedShareMessageIds = {};
  final Map<String, GlobalKey> _messageKeys = {};
  final List<_ChatSearchMatch> _searchMatches = [];
  final Set<String> _searchMatchedMessageIds = {};
  final Map<String, bool> _attachmentExistsCache = {};
  String? _expandedInputAction;
  Timer? _inputActionCollapseTimer;
  int _currentSearchMatch = -1;
  String _lastSearchSignature = '';
  String _lastSearchQuery = '';
  String? _searchRegexError;
  double _historyScrollOffset = 0;
  final Set<String> _collapsedHistoryRoleIds = {};
  int _historyScrollRestoreGeneration = 0;

  int _streamGen = 0;
  String? _streamingConvId;
  DateTime? _lastStreamUiUpdate;
  Timer? _streamWaitTimer;
  // Cancels slow pre-send work, such as image recognition, when the user starts
  // a new conversation or withdraws a message before the async work finishes.
  int _sendGen = 0;

  final List<_RetryEntry> _retryHistory = [];
  String? _retryMsgId;
  int _retryIdx = 0;

  late final ChatImageExporter _imageExporter = ChatImageExporter(
    controller: ScreenshotController(),
    nativeTools: _nativeToolsChannel,
    showSnack: _showShareImageSnack,
  );

  late stt.SpeechToText _speech;
  StreamSubscription<AgentRunEvent>? _sub;
  AgentRunHandle? _agentRun;
  String? _agentMessageId;
  AgentToolRegistry? _externalToolRegistry;
  AgentRunPersistenceLifecycle? _agentPersistence;
  AgentToolResultProcessor? _agentToolResultProcessor;
  WebSearchService? _webSearch;
  final AgentUserInteractionBroker _userInteractionBroker =
      AgentUserInteractionBroker();
  String? _shownUserInteractionId;
  BuildContext? _userInteractionDialogContext;
  String? _recordPath;
  int _recordingRequestGen = 0;
  bool _recordingStartCancelled = false;

  @override
  void initState() {
    super.initState();
    _historyScrollController = ScrollController(keepScrollOffset: false)
      ..addListener(_rememberHistoryScrollOffset);
    _attachmentStorage = AttachmentStorageService(
      storageV2: context.read<StorageV2Service>(),
    );
    final backend = context.read<BackendClient>();
    try {
      _externalToolRegistry = context.read<McpProvider>().toolRegistry;
    } on ProviderNotFoundException {
      // Focused provider graphs may intentionally omit optional MCP tools.
    }
    try {
      _agentPersistence = context.read<AgentRunPersistenceLifecycle>();
      _agentToolResultProcessor = context.read<AgentToolResultProcessor>();
    } on ProviderNotFoundException {
      // Focused provider graphs may intentionally omit durable run recording.
    }
    try {
      _webSearch = context.read<WebSearchService>();
    } on ProviderNotFoundException {
      // Focused widget tests may omit optional web search composition.
    }
    _ownsApi = widget.api == null;
    _api = widget.api ?? ApiService(backend: backend);
    _recognition = ModelRecognitionService(api: _api);
    _agentEnabled = context
        .read<SettingsProvider>()
        .settings
        .agentEnabledByDefault;
    _userInteractionBroker.addListener(_onUserInteractionChanged);
    WidgetsBinding.instance.addObserver(this);
    _searchCtrl.addListener(_refreshSearchMatches);
    _speech = stt.SpeechToText();
    if (widget.conversationId != null) {
      _convId = widget.conversationId;
      _applyConversationSettings(widget.conversationId!);
      widget.onConversationLoaded?.call();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _scheduleJumpToBottom(unfocusInput: true, waitForStableLayout: true);
        }
      });
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    widget.onBackHandlerChanged?.call(_handleBack);
    widget.onNewConversationHandlerChanged?.call(_startNewConversation);
  }

  void _onUserInteractionChanged() {
    final request = _userInteractionBroker.pendingFor(
      AgentUserInteractionSurface.mainChat,
    );
    if (request?.id != _shownUserInteractionId) {
      final dialogContext = _userInteractionDialogContext;
      if (dialogContext != null) Navigator.of(dialogContext).pop();
    }
    if (request == null || !mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted ||
          _userInteractionBroker
                  .pendingFor(AgentUserInteractionSurface.mainChat)
                  ?.id !=
              request.id) {
        return;
      }
      final answer = await _showAgentQuestion(request);
      if (!mounted) return;
      if (answer == null) {
        _userInteractionBroker.cancel(
          surface: AgentUserInteractionSurface.mainChat,
          requestId: request.id,
          reason: 'user_cancelled',
        );
      } else {
        _userInteractionBroker.answer(
          surface: AgentUserInteractionSurface.mainChat,
          requestId: request.id,
          answer: answer,
        );
      }
    });
  }

  Future<AgentUserAnswer?> _showAgentQuestion(
    AgentUserInteractionRequest request,
  ) async {
    final question = request.question;
    if (question.kind == AgentUserQuestionKind.confirm) {
      final confirmed = await _showUserInteractionDialog<bool>(
        requestId: request.id,
        builder: (dialogContext) => AlertDialog(
          title: Text(question.prompt),
          content: question.detail == null ? null : Text(question.detail!),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('否'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('是'),
            ),
          ],
        ),
      );
      return confirmed == null ? null : AgentUserAnswer.confirm(confirmed);
    }
    if (question.kind == AgentUserQuestionKind.singleChoice) {
      final choice = await _showUserInteractionDialog<String>(
        requestId: request.id,
        builder: (dialogContext) => SimpleDialog(
          title: Text(question.prompt),
          children: question.choices
              .map(
                (choice) => SimpleDialogOption(
                  onPressed: () => Navigator.pop(dialogContext, choice.id),
                  child: Text(choice.label),
                ),
              )
              .toList(growable: false),
        ),
      );
      return choice == null ? null : AgentUserAnswer.singleChoice(choice);
    }
    if (question.kind == AgentUserQuestionKind.multipleChoice) {
      final selected = <String>{};
      final choices = await _showUserInteractionDialog<Set<String>>(
        requestId: request.id,
        builder: (dialogContext) => StatefulBuilder(
          builder: (context, setDialogState) => AlertDialog(
            title: Text(question.prompt),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: question.choices
                  .map(
                    (choice) => CheckboxListTile(
                      value: selected.contains(choice.id),
                      title: Text(choice.label),
                      onChanged: (value) => setDialogState(() {
                        value == true
                            ? selected.add(choice.id)
                            : selected.remove(choice.id);
                      }),
                    ),
                  )
                  .toList(growable: false),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed:
                    selected.length < question.minSelections ||
                        selected.length >
                            (question.maxSelections ?? question.choices.length)
                    ? null
                    : () => Navigator.pop(
                        dialogContext,
                        Set<String>.from(selected),
                      ),
                child: const Text('确定'),
              ),
            ],
          ),
        ),
      );
      return choices == null ? null : AgentUserAnswer.multipleChoice(choices);
    }
    final controller = TextEditingController();
    final text = await _showUserInteractionDialog<String>(
      requestId: request.id,
      builder: (dialogContext) => AlertDialog(
        title: Text(question.prompt),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: InputDecoration(hintText: question.detail),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: const Text('提交'),
          ),
        ],
      ),
    );
    controller.dispose();
    return text == null || text.trim().isEmpty
        ? null
        : AgentUserAnswer.text(text);
  }

  Future<T?> _showUserInteractionDialog<T>({
    required String requestId,
    required WidgetBuilder builder,
  }) async {
    _shownUserInteractionId = requestId;
    try {
      return await showDialog<T>(
        context: context,
        builder: (dialogContext) {
          _userInteractionDialogContext = dialogContext;
          return builder(dialogContext);
        },
      );
    } finally {
      if (_shownUserInteractionId == requestId) {
        _shownUserInteractionId = null;
        _userInteractionDialogContext = null;
      }
    }
  }

  bool _handleBack() {
    if (_showSearch) {
      _closeSearch();
      return true;
    }
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
      if (_streaming && _streamingConvId != widget.conversationId) {
        _stopStreaming();
      }
      _sendGen++;
      setState(() {
        _preparingSend = false;
        _convId = widget.conversationId;
        _clearPendingState();
        _clearRetryState();
      });
      _applyConversationSettings(widget.conversationId!);
      widget.onConversationLoaded?.call();
      _closeSearch();
      _scheduleJumpToBottom(unfocusInput: true, waitForStableLayout: true);
    } else if (widget.active && !old.active) {
      _scheduleJumpToBottom(unfocusInput: true, waitForStableLayout: true);
    }
  }

  ConversationSettings _roleSettings(ModelConfig model) {
    final sp = context.read<SettingsProvider>();
    final settings = sp.settings;
    final role = sp.currentRole;
    return ConversationSettings(
      modelId: role.modelId ?? model.id,
      modelName: role.modelName ?? model.modelName,
      thinking: _thinking,
      agentEnabled: _agentEnabled,
      selectedSystemPromptId: role.id == ChatRole.defaultId ? null : role.id,
      systemPrompt: role.systemPrompt,
      speechModelId: settings.speechModelId,
      imageModelId: settings.imageModelId,
      imageOcrEnabled: settings.imageOcrEnabled,
      imageRecognitionModelId: settings.imageRecognitionModelId,
      imageRecognitionEnabled: settings.imageRecognitionEnabled,
      imageRecognitionPrompt: settings.imageRecognitionPrompt,
      imageGenerationModelId: settings.imageGenerationModelId,
      imageGenerationEnabled: settings.imageGenerationEnabled,
    );
  }

  void _applyConversationSettings(String conversationId) {
    final conv = context.read<ConversationProvider>().getConversation(
      conversationId,
    );
    if (conv == null) return;
    _draftSettings = null;
    _thinking = conv.settings.thinking;
    _agentEnabled = conv.settings.agentEnabled;
  }

  @override
  void dispose() {
    widget.onBackHandlerChanged?.call(() => false);
    widget.onBackAvailabilityChanged?.call(false);
    widget.onNewConversationHandlerChanged?.call(() {});
    _agentRun?.cancel();
    _userInteractionBroker.cancelSurface(
      AgentUserInteractionSurface.mainChat,
      reason: 'surface_disposed',
    );
    _userInteractionBroker.removeListener(_onUserInteractionChanged);
    _userInteractionBroker.dispose();
    _sub?.cancel();
    _setBackgroundGenerationActive(false);
    _inputActionCollapseTimer?.cancel();
    _streamWaitTimer?.cancel();
    _recordingStartCancelled = true;
    _recordingRequestGen++;
    unawaited(_speech.stop());
    unawaited(_audioRecorder.stop());
    _audioRecorder.dispose();
    _streamDraft.dispose();
    _inputRevision.dispose();
    _searchCtrl.removeListener(_refreshSearchMatches);
    _searchCtrl.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _historyScrollRestoreGeneration++;
    _historyScrollController.removeListener(_rememberHistoryScrollOffset);
    _historyScrollController.dispose();
    _focusNode.dispose();
    _searchFocusNode.dispose();
    if (_ownsApi) _api.dispose();
    _recognition.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _setStreaming(bool value) {
    if (_streaming == value) return;
    if (!value) {
      _streamingConvId = null;
      _lastStreamUiUpdate = null;
      _updateStreamDraft(const _StreamDraft());
    }
    _streaming = value;
    _setBackgroundGenerationActive(value);
  }

  void _beginStreaming(String conversationId) {
    _unfocusComposerOnMobile();
    _streamingConvId = conversationId;
    _lastStreamUiUpdate = null;
    _updateStreamDraft(const _StreamDraft());
    _setStreaming(true);
  }

  void _updateStreamDraft(_StreamDraft draft) {
    final current = _streamDraft.value;
    if (current.content == draft.content &&
        current.thinking == draft.thinking &&
        current.status == draft.status &&
        current.activeToolName == draft.activeToolName &&
        current.activeSkillDisplayName == draft.activeSkillDisplayName) {
      return;
    }
    _streamDraft.value = draft;
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
      _generationBackgroundService.setActive(active).catchError((
        Object error,
        StackTrace stackTrace,
      ) {
        debugPrint(
          '切换生成前台服务失败 (${active ? 'start' : 'stop'}): '
          '$error\n$stackTrace',
        );
      }),
    );
  }

  void _clearAbortedStreaming(String reason, {String? conversationId}) {
    debugPrint('清理未启动的生成流: $reason');
    if (!_streaming ||
        (conversationId != null && _streamingConvId != conversationId)) {
      return;
    }
    _streamWaitTimer?.cancel();
    _streamWaitTimer = null;
    unawaited(_sub?.cancel());
    _sub = null;
    _agentRun?.cancel();
    _agentRun = null;
    _agentMessageId = null;
    setState(() => _setStreaming(false));
  }

  void _clearRetryState() {
    _retryHistory.clear();
    _retryMsgId = null;
    _retryIdx = 0;
  }

  // 清空流式输出中间态：模型选择、思维链、附件等临时数据。
  void _clearPendingState() {
    _pendingModelId = null;
    _draftSettings = null;
    _thinkingTxt = null;
    _updateStreamDraft(const _StreamDraft());
    _thinkExpanded = false;
    _expandedThinkIds.clear();
    _thinkMap.clear();
    _pendingImages.clear();
  }

  void _syncBackAvailability() {
    widget.onBackAvailabilityChanged?.call(_showSearch || _shareSelecting);
  }

  bool get _isNearBottom {
    if (!_scrollCtrl.hasClients) return true;
    final pos = _scrollCtrl.position;
    return pos.maxScrollExtent - pos.pixels <= 48;
  }

  bool get _isMobilePlatform => Platform.isAndroid || Platform.isIOS;

  double _currentBottomInset() {
    final view = View.maybeOf(context);
    if (view != null) return view.viewInsets.bottom / view.devicePixelRatio;
    return MediaQuery.maybeOf(context)?.viewInsets.bottom ?? 0;
  }

  void _handleInputTap() {
    if (!_isMobilePlatform) return;
    _keyboardLiftRequestedByInputTap = _lastBottomInset <= 0;
    _keyboardShouldLiftMessages = _autoScrollToBottom && _isNearBottom;
  }

  void _unfocusComposerOnMobile() {
    if (!_isMobilePlatform) return;
    _focusNode.unfocus();
    _keyboardLiftRequestedByInputTap = false;
    _keyboardShouldLiftMessages = false;
  }

  // 根据滚动位置同步“是否接近底部”状态，控制自动跟随和回底按钮。
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
    _keyboardLiftRequestedByInputTap = false;
    _keyboardShouldLiftMessages = false;
    setState(() {
      _autoScrollToBottom = false;
      _showScrollToBottom = true;
    });
  }

  void _scrollEnd({bool force = false}) {
    if (SystemScrollCaptureService.instance.isCapturing) return;
    if (!force && !_autoScrollToBottom) return;
    if (!force) {
      final now = DateTime.now();
      final last = _lastAutoScrollAt;
      if (_scrollEndScheduled ||
          (last != null && now.difference(last).inMilliseconds < 120)) {
        return;
      }
      _lastAutoScrollAt = now;
    }
    _scrollEndScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollEndScheduled = false;
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

  void _scheduleJumpToBottom({
    bool unfocusInput = false,
    bool waitForStableLayout = false,
  }) {
    if (unfocusInput && _isMobilePlatform) {
      _unfocusComposerOnMobile();
    }
    setState(() {
      _autoScrollToBottom = true;
      _showScrollToBottom = false;
    });
    if (waitForStableLayout) {
      _jumpToBottomAfterStableLayout();
      return;
    }
    _scrollEnd(force: true);
  }

  void _jumpToBottomAfterStableLayout() {
    final scrollGen = ++_scrollGen;

    void jump(int remaining, double previousMaxExtent) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || scrollGen != _scrollGen) return;
        if (!_scrollCtrl.hasClients) {
          if (remaining > 0) jump(remaining - 1, previousMaxExtent);
          return;
        }
        final position = _scrollCtrl.position;
        final target = position.maxScrollExtent;
        if ((target - position.pixels).abs() > 0.5) {
          position.jumpTo(target);
        }
        final layoutChanged = (target - previousMaxExtent).abs() > 0.5;
        if (remaining > 0 && (layoutChanged || !_isNearBottom)) {
          jump(remaining - 1, target);
          return;
        }
        _syncBottomState();
      });
    }

    jump(8, -1);
  }

  void _jumpToBottom() {
    _scheduleJumpToBottom();
  }

  void _openSearch() {
    final conv = _convId == null
        ? null
        : context.read<ConversationProvider>().getConversation(_convId!);
    if (conv == null || conv.messages.isEmpty) return;
    if (_shareSelecting) _cancelShareSelection();
    setState(() => _showSearch = true);
    _refreshSearchMatches();
    _syncBackAvailability();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocusNode.requestFocus();
    });
  }

  void _closeSearch() {
    if (!_showSearch) return;
    _searchFocusNode.unfocus();
    _searchCtrl.clear();
    setState(() {
      _showSearch = false;
      _searchMatches.clear();
      _searchMatchedMessageIds.clear();
      _currentSearchMatch = -1;
      _lastSearchSignature = '';
      _lastSearchQuery = '';
      _searchRegexError = null;
    });
    _syncBackAvailability();
  }

  GlobalKey _messageKeyFor(String messageId) {
    return _messageKeys.putIfAbsent(messageId, GlobalKey.new);
  }

  void _pruneMessageKeys(List<Message> messages) {
    final ids = messages.map((message) => message.id).toSet();
    _messageKeys.removeWhere((id, _) => !ids.contains(id));
  }

  void _refreshSearchMatches() {
    if (!mounted) return;
    final query = _searchCtrl.text.trim();
    final matcher = ChatSearchMatcher.fromQuery(query);
    final conv = _convId == null
        ? null
        : context.read<ConversationProvider>().getConversation(_convId!);
    final messages = conv?.messages ?? const <Message>[];
    final signature = [
      query,
      _convId ?? '',
      matcher.regexError ?? '',
      for (final message in messages) '${message.id}:${message.content.length}',
      for (final message in messages) message.content.hashCode,
      for (final message in messages)
        message.images.map((image) => image.name).join('\u{1f}'),
    ].join('|');
    if (signature == _lastSearchSignature) return;
    final queryChanged = query != _lastSearchQuery;

    final matches = <_ChatSearchMatch>[];
    final matchedMessageIds = <String>{};
    if (!matcher.isEmpty && !matcher.hasError) {
      for (var i = 0; i < messages.length; i++) {
        final message = messages[i];
        for (final range in matcher.rangesIn(message.content)) {
          matches.add(
            _ChatSearchMatch(
              messageId: message.id,
              messageIndex: i,
              start: range.start,
              end: range.end,
            ),
          );
          matchedMessageIds.add(message.id);
        }
        for (final image in message.images) {
          if (!matcher.matches(image.name)) continue;
          matches.add(
            _ChatSearchMatch(
              messageId: message.id,
              messageIndex: i,
              start: -1,
              end: -1,
            ),
          );
          matchedMessageIds.add(message.id);
        }
      }
    }

    final previous =
        _currentSearchMatch >= 0 && _currentSearchMatch < _searchMatches.length
        ? _searchMatches[_currentSearchMatch]
        : null;
    var current = _currentSearchMatch;
    if (matches.isEmpty) {
      current = -1;
    } else if (!queryChanged && previous != null) {
      final retained = matches.indexWhere(
        (match) =>
            match.messageId == previous.messageId &&
            match.start == previous.start &&
            match.end == previous.end,
      );
      current = retained >= 0 ? retained : current;
    } else {
      current = matches.length - 1;
    }
    if (matches.isNotEmpty && (current < 0 || current >= matches.length)) {
      current = matches.length - 1;
    }
    final shouldScroll =
        _showSearch &&
        query.isNotEmpty &&
        matcher.regexError == null &&
        current >= 0;
    setState(() {
      _lastSearchSignature = signature;
      _lastSearchQuery = query;
      _searchRegexError = matcher.regexError;
      _searchMatches
        ..clear()
        ..addAll(matches);
      _searchMatchedMessageIds
        ..clear()
        ..addAll(matchedMessageIds);
      _currentSearchMatch = current;
    });
    if (shouldScroll) _scrollToSearchMatch(current);
  }

  void _selectSearchMatch(int index) {
    if (_searchMatches.isEmpty) return;
    final next = index % _searchMatches.length;
    final normalized = next < 0 ? next + _searchMatches.length : next;
    setState(() => _currentSearchMatch = normalized);
    _scrollToSearchMatch(normalized);
  }

  void _nextSearchMatch() => _selectSearchMatch(_currentSearchMatch + 1);

  void _previousSearchMatch() => _selectSearchMatch(_currentSearchMatch - 1);

  void _scrollToSearchMatch(int index) {
    if (index < 0 || index >= _searchMatches.length) return;
    final match = _searchMatches[index];
    final key = _messageKeyFor(match.messageId);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_ensureSearchMatchVisible(key)) return;
      final conv = _convId == null
          ? null
          : context.read<ConversationProvider>().getConversation(_convId!);
      final count = conv?.messages.length ?? 0;
      if (!_scrollCtrl.hasClients || count <= 1) return;
      final maxScroll = _scrollCtrl.position.maxScrollExtent;
      final estimatedOffset = (maxScroll * match.messageIndex / (count - 1))
          .clamp(_scrollCtrl.position.minScrollExtent, maxScroll);
      final scrollGen = ++_scrollGen;
      _scrollCtrl
          .animateTo(
            estimatedOffset,
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOut,
          )
          .then((_) {
            if (!mounted || scrollGen != _scrollGen) return;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted && scrollGen == _scrollGen) {
                _ensureSearchMatchVisible(key);
              }
            });
          });
    });
  }

  bool _ensureSearchMatchVisible(GlobalKey? key) {
    final targetContext = key?.currentContext;
    if (targetContext == null) return false;
    Scrollable.ensureVisible(
      targetContext,
      duration: const Duration(milliseconds: 220),
      curve: Curves.easeOut,
      alignment: 0.35,
    );
    return true;
  }

  bool _messageHasSearchMatch(String messageId) {
    return _searchMatchedMessageIds.contains(messageId);
  }

  bool _isCurrentSearchMessage(String messageId) {
    final index = _currentSearchMatch;
    return index >= 0 &&
        index < _searchMatches.length &&
        _searchMatches[index].messageId == messageId;
  }

  bool _isCurrentTextRange(String messageId, int start, int end) {
    final index = _currentSearchMatch;
    if (index < 0 || index >= _searchMatches.length) return false;
    final match = _searchMatches[index];
    return match.messageId == messageId &&
        match.start == start &&
        match.end == end;
  }

  double _assistantContentMaxWidth() {
    final width = MediaQuery.sizeOf(context).width;
    if (width < 600) return width * 0.92;
    if (width < 1000) return width * 0.86;
    final maxWidth = width * 0.78;
    return maxWidth > 900 ? 900 : maxWidth;
  }

  Widget _searchableUserText(Message msg) {
    final query = _searchCtrl.text.trim();
    final highlights = <_UserTextHighlight>[];
    if (!_showSearch || query.isEmpty || !_messageHasSearchMatch(msg.id)) {
      return _LinkAwareSelectableText(
        content: msg.content,
        onOpenLink: _openExternalLink,
        onExplainSelection: (text) => _showKnowledgeExplanation(
          text: text,
          message: msg,
          saveAutomatically: false,
        ),
      );
    }
    final matcher = ChatSearchMatcher.fromQuery(query);
    for (final range in matcher.rangesIn(msg.content)) {
      highlights.add(
        _UserTextHighlight(
          start: range.start,
          end: range.end,
          current: _isCurrentTextRange(msg.id, range.start, range.end),
        ),
      );
    }
    return _LinkAwareSelectableText(
      content: msg.content,
      highlights: highlights,
      onOpenLink: _openExternalLink,
      onExplainSelection: (text) => _showKnowledgeExplanation(
        text: text,
        message: msg,
        saveAutomatically: false,
      ),
    );
  }

  Future<void> _showKnowledgeExplanation({
    required String text,
    required Message message,
    String? categoryId,
    bool saveAutomatically = true,
  }) async {
    final cid = _convId;
    if (cid == null) return;
    final conversation = context.read<ConversationProvider>().getConversation(
      cid,
    );
    await showKnowledgeExplanationDialog(
      context: context,
      api: _api,
      text: text,
      categoryId: categoryId,
      sourceContext: message.content,
      sourceTitle: conversation?.title ?? '',
      sourceUrl: 'lynai://conversation/$cid/message/${message.id}',
      saveAutomatically: saveAutomatically,
    );
  }

  Future<void> _openExternalLink(String href) async {
    if (_shareSelecting) return;
    final uri = Uri.tryParse(href);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(shortSnackBar('无法打开该链接'));
      }
      return;
    }
    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!opened && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(shortSnackBar('无法打开该链接'));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(shortSnackBar('无法打开该链接'));
      }
    }
  }

  @override
  void didChangeMetrics() {
    super.didChangeMetrics();
    if (!mounted) return;
    final bottomInset = _currentBottomInset();
    final keyboardOpening = bottomInset > _lastBottomInset;
    if (bottomInset <= 0) {
      _keyboardLiftRequestedByInputTap = false;
      _keyboardShouldLiftMessages = false;
    }
    if (keyboardOpening &&
        _keyboardLiftRequestedByInputTap &&
        _keyboardShouldLiftMessages &&
        _autoScrollToBottom) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _scrollEnd(force: true);
      });
    }
    _lastBottomInset = bottomInset;
  }

  void _showMissingChatModelTip() {
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('请先在设置中添加 AI 模型')));
  }

  void _stopStreaming() {
    _userInteractionBroker.cancelSurface(
      AgentUserInteractionSurface.mainChat,
      reason: 'user_stopped',
    );
    if (!_streaming) return;
    _streamWaitTimer?.cancel();
    _streamWaitTimer = null;
    final cid = _streamingConvId ?? _convId;
    _streamGen++;
    final run = _agentRun;
    final messageId = _agentMessageId;
    run?.cancel();
    _agentRun = null;
    _agentMessageId = null;
    unawaited(_sub?.cancel());
    _sub = null;
    if (!mounted) return;
    setState(() => _setStreaming(false));
    if (cid == null) return;
    if (run == null || messageId == null) return;
    unawaited(
      run.result.then((result) {
        if (!mounted || result.runId != run.id) return;
        final partial = result.partialContent.trim();
        context.read<ConversationProvider>().updateMessageContent(
          cid,
          messageId,
          partial.isEmpty ? '已停止生成' : '$partial\n\n---\n已停止生成',
          thinkingContent: result.reasoning,
        );
      }),
    );
  }

  ModelConfig? _getModel(ModelConfigProvider mp) {
    final chatModels = mp.enabledModelsByCategory(ModelConfig.categoryChat);
    if (chatModels.isEmpty) return null;
    if (_convId != null) {
      final conv = context.read<ConversationProvider>().getConversation(
        _convId!,
      );
      if (conv != null) {
        try {
          final model = chatModels.firstWhere((m) => m.id == conv.modelId);
          final modelName = conv.settings.modelName;
          return modelName == null || modelName.isEmpty
              ? model
              : model.copyWith(modelName: modelName);
        } catch (_) {}
      }
    }
    if (_pendingModelId != null) {
      try {
        return chatModels.firstWhere((m) => m.id == _pendingModelId);
      } catch (_) {}
    }
    final role = context.read<SettingsProvider>().currentRole;
    final roleModelId = role.modelId;
    if (_convId == null && roleModelId != null && roleModelId.isNotEmpty) {
      try {
        final model = chatModels.firstWhere((m) => m.id == roleModelId);
        final modelName = role.modelName;
        return modelName == null || modelName.isEmpty
            ? model
            : model.copyWith(modelName: modelName);
      } catch (_) {}
    }
    final settings = _draftSettings;
    if (settings != null) {
      try {
        final model = chatModels.firstWhere((m) => m.id == settings.modelId);
        final modelName = settings.modelName;
        return modelName == null || modelName.isEmpty
            ? model
            : model.copyWith(modelName: modelName);
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
      if (conv != null) {
        return conv.settings.copyWith(
          thinking: _thinking,
          agentEnabled: _agentEnabled,
        );
      }
    }
    if (_draftSettings != null) {
      return _draftSettings!.copyWith(
        modelId: model.id,
        modelName: model.modelName,
        thinking: _thinking,
        agentEnabled: _agentEnabled,
      );
    }
    final role = context.read<SettingsProvider>().currentRole;
    if (role.id != ChatRole.defaultId || role.modelId != null) {
      return _roleSettings(model).copyWith(
        modelId: role.modelId ?? model.id,
        modelName: role.modelName ?? model.modelName,
      );
    }
    final set = context.read<SettingsProvider>().settings;
    final prompt = context.read<SettingsProvider>().effectiveSystemPrompt;
    return ConversationSettings(
      modelId: model.id,
      modelName: model.modelName,
      thinking: _thinking,
      agentEnabled: _agentEnabled,
      selectedSystemPromptId: set.selectedSystemPromptId,
      systemPrompt: prompt,
      speechModelId: set.speechModelId,
      imageModelId: set.imageModelId,
      imageOcrEnabled: set.imageOcrEnabled,
      imageRecognitionModelId: set.imageRecognitionModelId,
      imageRecognitionEnabled: set.imageRecognitionEnabled,
      imageRecognitionPrompt: set.imageRecognitionPrompt,
      imageGenerationModelId: set.imageGenerationModelId,
      imageGenerationEnabled: set.imageGenerationEnabled,
    );
  }

  void _saveDraftSettings(ConversationSettings settings) {
    _draftSettings = settings;
    _agentEnabled = settings.agentEnabled;
  }

  void _saveConversationSettings(ConversationSettings settings) {
    if (_convId != null) {
      _agentEnabled = settings.agentEnabled;
      context.read<ConversationProvider>().updateConversationSettings(
        _convId!,
        settings,
      );
    } else {
      _saveDraftSettings(settings);
      return;
    }
  }

  ConversationSettings? _activeSettings() {
    if (_convId != null) {
      final conv = context.read<ConversationProvider>().getConversation(
        _convId!,
      );
      if (conv != null) {
        return conv.settings.copyWith(
          thinking: _thinking,
          agentEnabled: _agentEnabled,
        );
      }
    }
    return _draftSettings;
  }

  ConversationSettings _imageRecognitionSettings() {
    return _activeSettings() ?? _settingsToConversationSettings();
  }

  ComposerSelectorRegistry _selectorRegistryOf() {
    final registry = buildBuiltInSelectorRegistry(
      features: context.read<FeatureProvider>(),
      tasks: context.read<TaskProvider>(),
    );
    final features = context.read<FeatureProvider>();
    final tasks = context.read<TaskProvider>();
    final calendar = context.read<CalendarProvider>();
    final modelConfigs = context.read<ModelConfigProvider>();
    final pluginProvider = context.read<PluginProvider>();
    final settings = context.read<SettingsProvider>();
    final runtime = PluginLuaRuntimeService();
    for (final plugin in pluginProvider.plugins) {
      for (final command in plugin.manifest.commands) {
        registry.register(
          ComposerSelector(
            name: 'plugin.${plugin.id}.${command.name}',
            title: command.title,
            description: command.description,
            modelId: command.model,
            load: (query, path) async => parsePluginCommandItems(
              await runtime.executeCommandHandler(
                plugin: plugin,
                command: command,
                arguments: {'query': query, 'path': path},
                features: features,
                tasks: tasks,
                calendar: calendar,
                modelConfigs: modelConfigs,
                plugins: pluginProvider,
                settings: settings,
              ),
            ),
          ),
        );
      }
    }
    return registry;
  }

  void _insertComposerReference(ComposerSelectorValue value, String? modelId) {
    final reference = ComposerReference(
      localId: 'ref-${_refSeq++}',
      type: value.type,
      id: value.id,
      title: value.title,
      subtitle: value.subtitle,
      qualifiers: value.qualifiers,
    );
    _msgCtrl.insertReference(reference);
    if (modelId != null && modelId.isNotEmpty) {
      _pendingModelId = modelId;
    }
    _inputRevision.value++;
    setState(() {
      _showCommandPalette = false;
    });
    if (!_isMobilePlatform) _focusNode.requestFocus();
  }

  Future<void> _send() async {
    final displayText = _msgCtrl.displayText.trim();
    final modelText = _msgCtrl.modelText;
    final segments = _msgCtrl.segments;
    if ((displayText.isEmpty &&
            modelText.isEmpty &&
            _pendingImages.isEmpty) ||
        _streaming ||
        _preparingSend) {
      return;
    }
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    if (mp.enabledModelsByCategory(ModelConfig.categoryChat).isEmpty) {
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
    final targetConvId = _convId;
    final sendGen = ++_sendGen;
    setState(() => _preparingSend = true);
    final preparedUserContent = await _prepareUserContent(modelText, images);
    if (!mounted) return;
    if (sendGen != _sendGen || _convId != targetConvId) {
      _setBackgroundGenerationActive(false);
      return;
    }
    if (preparedUserContent == null) {
      setState(() => _preparingSend = false);
      _setBackgroundGenerationActive(false);
      return;
    }

    final isNewConversation = _convId == null;
    if (isNewConversation) {
      _convId = cp.createConversationWithMessages(
        conversationSettings,
        roleId: roleId,
        messages: [
          (
            role: 'user',
            content: displayText,
            images: images,
            composerSegments: segments,
          ),
          (
            role: 'assistant',
            content: '',
            images: const <MessageImage>[],
            composerSegments: const <ComposerSegment>[],
          ),
        ],
        modelContextByIndex: {0: preparedUserContent.textContext},
      );
    } else {
      cp.addMessage(
        _convId!,
        'user',
        displayText,
        modelContextContent: preparedUserContent.textContext,
        images: images,
        composerSegments: segments,
      );
      cp.addMessage(_convId!, 'assistant', '', save: false);
    }
    final cid = _convId!;
    _pendingModelId = null;
    _clearRetryState();
    _msgCtrl.clear();
    _inputRevision.value++;
    setState(() {
      _preparingSend = false;
      _pendingImages.clear();
      _beginStreaming(cid);
      _thinkingTxt = null;
    });
    _scrollEnd(force: true);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!_streaming || _convId != cid || sendGen != _sendGen) {
      _clearAbortedStreaming('发送准备完成后状态已失效', conversationId: cid);
      return;
    }
    _doSend(
      model,
      lastUserContentOverride: preparedUserContent.apiContent,
      createTitle: isNewConversation,
    );
  }

  void _doSend(
    ModelConfig model, {
    Object? lastUserContentOverride,
    bool createTitle = false,
  }) {
    final cid = _convId;
    if (cid == null) {
      _clearAbortedStreaming('流式请求缺少对话 ID');
      return;
    }
    final conv = context.read<ConversationProvider>().getConversation(cid);
    if (conv == null) {
      _clearAbortedStreaming('流式请求对应的对话不存在', conversationId: cid);
      return;
    }
    final annotationPrompt = const KnowledgeAnnotationPromptFormatter().format(
      context.read<KnowledgeProvider>().knowledgeAnnotationPromptSnapshot,
    );
    final msgs = buildApiMessages(
      conv,
      context.read<PluginProvider>().plugins,
      lastUserContentOverride: lastUserContentOverride,
      enableTools: _supportsNativeTools(model),
      annotationPrompt: annotationPrompt,
    );
    unawaited(_doStream(model, cid, msgs, createTitle: createTitle));
  }

  Future<void> _sendRetry(String text) async {
    final cid = _convId;
    if (_streaming || _preparingSend || cid == null) return;
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    final model = _getModel(mp);
    if (model == null) return;
    final conv = cp.getConversation(cid);
    if (conv == null) return;
    final lastUser = conv.messages.where((m) => m.role == 'user').last;
    _PreparedUserContent? preparedUserContent;
    final sendGen = ++_sendGen;
    setState(() => _preparingSend = true);
    try {
      preparedUserContent = await _prepareUserContent(text, lastUser.images);
      if (!mounted) return;
      if (sendGen != _sendGen || _convId != cid) return;
      if (preparedUserContent == null) {
        setState(() => _preparingSend = false);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _preparingSend = false);
      return;
    }
    _retryMsgId = lastUser.id;

    final lastAssistant = conv.messages
        .where((m) => m.role == 'assistant')
        .toList();
    if (lastAssistant.isNotEmpty &&
        (lastAssistant.last.content.isNotEmpty ||
            lastAssistant.last.images.isNotEmpty)) {
      _saveRetryHistoryEntry(
        lastUser.content,
        lastUser.images,
        lastAssistant.last.id,
        lastAssistant.last.content,
        lastAssistant.last.images,
        lastAssistant.last.thinkingContent,
      );
    }

    _retryHistory.add(_RetryEntry(text, lastUser.images));
    _retryIdx = _retryHistory.length - 1;
    cp.updateMessageContent(
      cid,
      lastUser.id,
      text,
      modelContextContent: preparedUserContent.textContext,
    );
    if (lastAssistant.isNotEmpty) {
      _thinkMap.remove(lastAssistant.last.id);
      cp.deleteMessage(cid, lastAssistant.last.id);
    }
    _scrollEnd(force: true);
    cp.addMessage(cid, 'assistant', '', save: false);
    setState(() {
      _preparingSend = false;
      _beginStreaming(cid);
      _thinkingTxt = null;
    });
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!_streaming || _convId != cid || sendGen != _sendGen) {
      _clearAbortedStreaming('重试准备完成后状态已失效', conversationId: cid);
      return;
    }
    _doSend(model, lastUserContentOverride: preparedUserContent.apiContent);
  }

  bool _supportsNativeTools(ModelConfig model) => model.supportsNativeTools;

  bool _supportsThinking(ModelConfig model) => model.supportsThinking;

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

  Future<void> _doStream(
    ModelConfig model,
    String cid,
    List<Map<String, dynamic>> msgs, {
    bool createTitle = false,
  }) async {
    if (!mounted) return;
    final sendGen = _sendGen;
    bool webSearchConfigured = false;
    try {
      webSearchConfigured =
          await (_webSearch?.isConfigured() ?? Future.value(false));
    } catch (error) {
      debugPrint('查询网页搜索配置失败，按未配置处理: $error');
    }
    if (!mounted) return;
    if (!_streaming || _streamingConvId != cid || sendGen != _sendGen) {
      final conv = context.read<ConversationProvider>().getConversation(cid);
      final last = conv?.messages.lastOrNull;
      if (last != null && last.role == 'assistant' && last.content.isEmpty) {
        context.read<ConversationProvider>().updateMessageContent(
          cid,
          last.id,
          '已停止生成',
        );
      }
      return;
    }
    final allowTools = _supportsNativeTools(model);
    final cp = context.read<ConversationProvider>();
    final streamSettings = cp.getConversation(cid)?.settings;
    final gen = ++_streamGen;
    String buf = '', thinkBuf = '';
    var timeoutDisplayed = false;

    void emitDraft({String? status}) {
      _updateStreamDraft(
        _StreamDraft(
          content: buf,
          thinking: thinkBuf.isEmpty ? null : thinkBuf,
          status: status,
        ),
      );
      _scrollEnd();
    }

    void armWaitTimeout() {
      _streamWaitTimer?.cancel();
      _streamWaitTimer = Timer(_streamWaitTimeout, () {
        if (!mounted || gen != _streamGen || !_streaming) return;
        timeoutDisplayed = true;
        emitDraft(status: '请求等待已超过 5 分钟，仍在继续接收模型返回。');
      });
    }

    void clearWaitTimeout() {
      _streamWaitTimer?.cancel();
      _streamWaitTimer = null;
    }

    final externalToolSnapshot = _externalToolRegistry?.snapshot();
    final storage = context.read<StorageV2Service>();
    _agentMessageId = cp.getConversation(cid)?.messages.lastOrNull?.id;
    final resolvedPermissionSnapshot =
        context.read<SettingsProvider>().settings.agentPermissionSnapshot;
    final toolService = ToolCallService(
      context.read<FeatureProvider>(),
      tasks: context.read<TaskProvider>(),
      calendar: context.read<CalendarProvider>(),
      knowledge: context.read<KnowledgeProvider>(),
      plugins: context.read<PluginProvider>(),
      modelConfigs: context.read<ModelConfigProvider>(),
      settings: context.read<SettingsProvider>(),
      conversations: context.read<ConversationProvider>(),
      backend: context.read<BackendClient>(),
      conversationId: cid,
      persistence: _agentPersistence,
      externalToolRegistry: _externalToolRegistry,
      externalToolSnapshot: externalToolSnapshot,
      storage: storage,
      resultSanitizer: AgentToolResultSanitizer.storageV2(storage),
      toolResultProcessor: _agentToolResultProcessor,
      userInteractionBroker: _userInteractionBroker,
      webSearch: _webSearch,
      webSearchConfigured: webSearchConfigured,
      permissionSnapshot: resolvedPermissionSnapshot,
    );
    final runSnapshot = toolService.createRunSnapshot(
      agentEnabled: streamSettings?.agentEnabled == true,
      imageGenerationEnabled:
          streamSettings?.imageGenerationEnabled == true &&
          _imageGenerationModel(streamSettings) != null,
    );
    final tools = allowTools
        ? runSnapshot.openAITools
        : const <Map<String, dynamic>>[];
    final run = const AgentLoopRuntime().start(
      messages: msgs,
      maxToolRounds: ToolCallService.maxToolRounds,
      persistence: _agentPersistence,
      toolResultProcessor: _agentToolResultProcessor,
      persistenceMetadata: AgentRunPersistenceMetadata(
        conversationId: cid,
        permissionPolicy: resolvedPermissionSnapshot,
      ),
      model: (request) => const StreamChunkAgentAdapter().adapt(
        _api.sendStreamRequest(
          model,
          request.messages,
          thinking: _thinking && _supportsThinking(model),
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
      datasetBarrier: storage.runtimeBarrier,
    );
    _agentRun = run;
    unawaited(_sub?.cancel());
    armWaitTimeout();
    _sub = run.events.listen((event) {
      if (!mounted || gen != _streamGen || event.runId != run.id) return;
      armWaitTimeout();
      switch (event.kind) {
        case AgentRunEventKind.turnStarted:
          buf = '';
          thinkBuf = '';
        case AgentRunEventKind.textDelta:
          buf += event.text ?? '';
        case AgentRunEventKind.reasoningDelta:
          thinkBuf += event.text ?? '';
        case AgentRunEventKind.toolCalls:
          _shouldUpdateStreamUi(force: true);
          emitDraft(status: '正在调用工具...');
        case AgentRunEventKind.toolStarted:
          final call = event.toolCall;
          if (call != null) {
            final skillDisplayName = call.name == 'load_plugin_skill'
                ? ToolCallService.pluginSkillDisplayName(
                    context.read<PluginProvider>().plugins,
                    call.arguments,
                  )
                : null;
            _updateStreamDraft(
              _StreamDraft(
                content: buf,
                thinking: thinkBuf.isEmpty ? null : thinkBuf,
                activeToolName: call.name,
                activeSkillDisplayName: skillDisplayName,
              ),
            );
          }
        default:
          break;
      }
      if (event.kind == AgentRunEventKind.textDelta ||
          event.kind == AgentRunEventKind.reasoningDelta) {
        if (timeoutDisplayed && (buf.isNotEmpty || thinkBuf.isNotEmpty)) {
          timeoutDisplayed = false;
          emitDraft();
        } else if (_shouldUpdateStreamUi()) {
          emitDraft();
        }
      }
    });
    unawaited(
      run.result.then((result) {
        if (!mounted || gen != _streamGen || result.runId != run.id) return;
        _agentRun = null;
        _agentMessageId = null;
        clearWaitTimeout();
        if (result.isCancelled) return;
        if (!result.isSuccess) {
          setState(() => _setStreaming(false));
          final msg = result.error.toString().replaceFirst('Exception: ', '');
          final partial = result.partialContent.trim();
          final display = partial.isNotEmpty
              ? '$partial\n\n---\n请求失败: $msg'
              : '请求失败: $msg';
          cp.updateLastMessage(
            cid,
            display,
            thinkingContent: result.reasoning,
            save: true,
          );
          return;
        }
        final content = result.toolRoundLimitReached
            ? ToolCallService.toolRoundLimitMessage(result.content)
            : result.content.trim().isEmpty
            ? _emptyAssistantReply
            : result.content;
        final think = result.reasoning;
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
            _retryHistory[_retryIdx].assistantImages = List<MessageImage>.from(
              lastMsg.images,
            );
            _retryHistory[_retryIdx].thinkingContent = think;
          }
        }
        if (createTitle) unawaited(_maybeCreateConversationTitle(model, cid));
        _scrollEnd();
      }),
    );
  }

  void _switchModel(ModelConfig model) {
    if (_convId != null) {
      final cp = context.read<ConversationProvider>();
      final conv = cp.getConversation(_convId!);
      if (conv != null) {
        cp.updateConversationSettings(
          _convId!,
          conv.settings.copyWith(modelId: model.id, modelName: model.modelName),
        );
      }
    } else {
      _pendingModelId = model.id;
      _draftSettings = _currentConversationSettings(
        model,
      ).copyWith(modelId: model.id, modelName: model.modelName);
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
    final cid = _convId;
    if (cid == null || _streaming || _preparingSend) return;
    final cp = context.read<ConversationProvider>();
    final conv = cp.getConversation(cid);
    if (conv == null) return;
    final um = conv.messages.where((m) => m.role == 'user').toList();
    if (um.isEmpty) return;
    final assistantMessages = conv.messages
        .where((m) => m.role == 'assistant')
        .toList();
    if (assistantMessages.isEmpty) return;
    final lastUser = um.last;
    Object? apiUserContent;
    final sendGen = ++_sendGen;
    setState(() => _preparingSend = true);
    try {
      apiUserContent = await _retryUserContent(lastUser);
      if (!mounted) return;
      if (sendGen != _sendGen || _convId != cid) return;
      if (apiUserContent == null) {
        setState(() => _preparingSend = false);
        return;
      }
    } catch (_) {
      if (mounted) setState(() => _preparingSend = false);
      return;
    }
    _retryMsgId = lastUser.id;

    final lastAssistant = assistantMessages.last;
    if (lastAssistant.content.isNotEmpty || lastAssistant.images.isNotEmpty) {
      _saveRetryHistoryEntry(
        lastUser.content,
        lastUser.images,
        lastAssistant.id,
        lastAssistant.content,
        lastAssistant.images,
        lastAssistant.thinkingContent,
      );
    }

    _retryHistory.add(_RetryEntry(lastUser.content, lastUser.images));
    _retryIdx = _retryHistory.length - 1;
    _thinkMap.remove(lastAssistant.id);
    cp.deleteMessage(cid, lastAssistant.id);
    cp.addMessage(cid, 'assistant', '', save: false);
    setState(() {
      _preparingSend = false;
      _beginStreaming(cid);
      _thinkingTxt = null;
    });
    final retryModel = _getModel(context.read<ModelConfigProvider>());
    if (retryModel != null) {
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (!_streaming || _convId != cid || sendGen != _sendGen) {
        _clearAbortedStreaming('历史重试准备完成后状态已失效', conversationId: cid);
        return;
      }
      _doSend(retryModel, lastUserContentOverride: apiUserContent);
    } else {
      setState(() {
        _preparingSend = false;
        _setStreaming(false);
      });
      _showMissingChatModelTip();
    }
  }

  Future<void> _retryWithoutHistory() async {
    final cid = _convId;
    if (cid == null || _streaming || _preparingSend) return;
    final cp = context.read<ConversationProvider>();
    final conv = cp.getConversation(cid);
    if (conv == null) return;
    final assistantMessages = conv.messages
        .where((m) => m.role == 'assistant')
        .toList();
    if (assistantMessages.isEmpty) return;
    final lastAssistant = assistantMessages.last;
    final retryModel = _getModel(context.read<ModelConfigProvider>());
    if (retryModel != null) {
      final conv = cp.getConversation(cid);
      final userMessages = conv?.messages
          .where((m) => m.role == 'user')
          .toList();
      final lastUser = userMessages == null || userMessages.isEmpty
          ? null
          : userMessages.last;
      Object? apiUserContent;
      final sendGen = ++_sendGen;
      setState(() => _preparingSend = true);
      if (lastUser != null) {
        try {
          apiUserContent = await _retryUserContent(lastUser);
          if (!mounted) return;
          if (sendGen != _sendGen || _convId != cid) return;
          if (apiUserContent == null) {
            setState(() => _preparingSend = false);
            return;
          }
        } catch (e) {
          if (!mounted) return;
          setState(() => _preparingSend = false);
          return;
        }
      }
      _thinkMap.remove(lastAssistant.id);
      cp.deleteMessage(cid, lastAssistant.id);
      cp.addMessage(cid, 'assistant', '', save: false);
      setState(() {
        _preparingSend = false;
        _beginStreaming(cid);
        _thinkingTxt = null;
      });
      await WidgetsBinding.instance.endOfFrame;
      if (!mounted) return;
      if (!_streaming || _convId != cid || sendGen != _sendGen) {
        _clearAbortedStreaming('无历史重试准备完成后状态已失效', conversationId: cid);
        return;
      }
      _doSend(retryModel, lastUserContentOverride: apiUserContent);
    } else {
      setState(() {
        _preparingSend = false;
        _setStreaming(false);
      });
      _showMissingChatModelTip();
    }
  }

  void _saveRetryHistoryEntry(
    String userContent,
    List<MessageImage> userImages,
    String assistantId,
    String assistantContent,
    List<MessageImage> assistantImages,
    String? assistantThinkingContent,
  ) {
    final thinkingContent =
        _thinkingTxt ?? _thinkMap[assistantId] ?? assistantThinkingContent;
    if (_retryHistory.isEmpty) {
      final oldEntry = _RetryEntry(userContent, userImages);
      oldEntry.assistantId = assistantId;
      oldEntry.assistantContent = assistantContent;
      oldEntry.assistantImages = List<MessageImage>.from(assistantImages);
      oldEntry.thinkingContent = thinkingContent;
      _retryHistory.add(oldEntry);
    } else if (_retryIdx < _retryHistory.length) {
      _retryHistory[_retryIdx].userImages = userImages;
      _retryHistory[_retryIdx].assistantId = assistantId;
      _retryHistory[_retryIdx].assistantContent = assistantContent;
      _retryHistory[_retryIdx].assistantImages = List<MessageImage>.from(
        assistantImages,
      );
      _retryHistory[_retryIdx].thinkingContent = thinkingContent;
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
    if (_showSearch) _closeSearch();
    setState(() {
      _shareSelecting = true;
      _selectedShareMessageIds.clear();
      if (initialMessage != null) {
        _selectedShareMessageIds.add(initialMessage.id);
      }
    });
    _syncBackAvailability();
  }

  void _cancelShareSelection() {
    if (!_shareSelecting) return;
    setState(() {
      _shareSelecting = false;
      _selectedShareMessageIds.clear();
    });
    _syncBackAvailability();
  }

  void _toggleShareMessage(Message msg) {
    if (_sharingImage) return;
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
    final conv = context.read<ConversationProvider>().getConversation(_convId!);
    if (conv == null) return;
    final settings = context.read<SettingsProvider>().settings;
    final brightness = Theme.of(context).brightness;
    try {
      setState(() => _sharingImage = true);
      await _imageExporter.shareMessages(
        conv: conv,
        selectedIds: _selectedShareMessageIds,
        pageBuilder: (page, pageNumber, pageCount) => ShareConversationImage(
          title: conv.title,
          messages: page,
          seedColor: settings.themeColor,
          brightness: brightness,
          pageNumber: pageCount == 0 ? null : pageNumber,
          pageCount: pageCount == 0 ? null : pageCount,
        ),
        onSelectionCleared: _cancelShareSelection,
      );
    } finally {
      if (mounted) setState(() => _sharingImage = false);
    }
  }

  Future<void> _saveSelectedMessagesImage() async {
    if (_sharingImage || _convId == null || _selectedShareMessageIds.isEmpty) {
      return;
    }
    final conv = context.read<ConversationProvider>().getConversation(_convId!);
    if (conv == null) return;
    final settings = context.read<SettingsProvider>().settings;
    final brightness = Theme.of(context).brightness;
    try {
      setState(() => _sharingImage = true);
      await _imageExporter.saveMessages(
        conv: conv,
        selectedIds: _selectedShareMessageIds,
        pageBuilder: (page, pageNumber, pageCount) => ShareConversationImage(
          title: conv.title,
          messages: page,
          seedColor: settings.themeColor,
          brightness: brightness,
          pageNumber: pageCount == 0 ? null : pageNumber,
          pageCount: pageCount == 0 ? null : pageCount,
        ),
        onSelectionCleared: _cancelShareSelection,
      );
    } finally {
      if (mounted) setState(() => _sharingImage = false);
    }
  }

  String _previewImageFileName(String name) {
    final dot = name.lastIndexOf('.');
    final extension = dot >= 0 ? name.substring(dot).toLowerCase() : '.png';
    final safeExtension = RegExp(r'^\.[a-z0-9]{1,8}$').hasMatch(extension)
        ? extension
        : '.png';
    return 'lynai_image_${DateTime.now().millisecondsSinceEpoch}$safeExtension';
  }

  Future<void> _savePreviewImageToGallery(String path, String name) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (mounted) _showShareImageSnack('图片文件已不存在');
        return;
      }
      final bytes = await file.readAsBytes();
      final fileName = _previewImageFileName(name);
      if (Platform.isAndroid || Platform.isIOS) {
        final result = await _nativeToolsChannel
            .invokeMapMethod<String, dynamic>('saveImageToGallery', {
              'bytes': bytes,
              'fileName': fileName,
            });
        if (result?['ok'] != true) {
          throw Exception(result?['error'] ?? '保存到图库失败');
        }
        if (mounted) _showShareImageSnack('图片已保存到图库');
        return;
      }

      Directory? dir;
      if (isDesktopPlatform) {
        dir = await getDownloadsDirectory();
      }
      dir ??= await getApplicationDocumentsDirectory();
      final saved = File('${dir.path}/$fileName');
      await saved.writeAsBytes(bytes, flush: true);
      if (mounted) _showShareImageSnack('图片已保存到 ${saved.path}');
    } catch (e) {
      if (mounted) _showShareImageSnack('保存失败: $e');
    }
  }

  void _showShareImageSnack(String message) {
    showShortSnackBar(context, message);
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
      for (var i = 0; i < picked.length; i++) {
        final item = picked[i];
        images.add(
          _pendingImageFromStored(
            await _attachmentStorage.storeFile(
              File(item.path),
              directoryName: 'message_images',
              name: item.name,
              fallbackName: 'image',
              mimeType:
                  item.mimeType ??
                  AttachmentStorageService.inferMimeType(item.path),
            ),
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
    if (!mounted) return;
    setState(() {
      _pendingImages.addAll(images);
    });
  }

  Future<void> _pickFiles() async {
    if (_streaming) return;
    try {
      final result = await pickMultipleFilePayloads();
      if (!mounted || result.isEmpty) return;
      final files = <_PendingImage>[];
      for (final item in result) {
        files.add(await _storeAttachmentPayload(item));
        if (!mounted) return;
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
    if (_streaming || isDesktopPlatform) return;
    try {
      final picked = await ImagePicker().pickImage(source: ImageSource.camera);
      if (!mounted || picked == null) return;
      final file = await _storeAttachmentFile(
        File(picked.path),
        picked.name,
        mimeType:
            picked.mimeType ??
            AttachmentStorageService.inferMimeType(picked.path),
      );
      if (!mounted) return;
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
    return _pendingImageFromStored(
      await _attachmentStorage.storeFile(
        source,
        directoryName: 'message_attachments',
        name: name,
        mimeType: mimeType,
      ),
    );
  }

  Future<_PendingImage> _storeAttachmentPayload(
    PickedFilePayload source,
  ) async {
    return _pendingImageFromStored(
      await _attachmentStorage.storePayload(
        source,
        directoryName: 'message_attachments',
      ),
    );
  }

  _PendingImage _pendingImageFromStored(StoredAttachment stored) {
    return _PendingImage(
      path: stored.path,
      name: stored.name,
      size: stored.size,
      mimeType: stored.mimeType,
    );
  }

  Future<void> _handlePasteShortcut() async {
    if (_streaming) return;
    await _pasteClipboardImage();
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
      var timedOut = false;
      final completer = Completer<void>();
      final progress = reader.getFile(fileFormat, (file) async {
        if (timedOut) return;
        final bytes = await file.readAll();
        if (timedOut) return;
        final ext = _clipboardImageExtension(file.fileName, fileFormat);
        final name = _clipboardImageName(file.fileName, ext);
        await _addClipboardImage(bytes, name);
        pasted = true;
        if (!completer.isCompleted) completer.complete();
      });
      if (progress != null) {
        await completer.future.timeout(
          const Duration(seconds: 2),
          onTimeout: () {
            timedOut = true;
          },
        );
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
      final stored = await _attachmentStorage.storeBytes(
        bytes,
        directoryName: 'message_images',
        name: fileName,
        fallbackName: 'image',
      );
      if (!mounted) return;
      setState(() {
        _pendingImages.add(_pendingImageFromStored(stored));
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('粘贴图片失败: $e')));
    }
  }

  Future<_PreparedUserContent?> _prepareUserContent(
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

  Future<Object?> _retryUserContent(Message message) async {
    return retryUserContent(message, () async {
      return (await _prepareUserContent(
        message.content,
        message.images,
      ))?.apiContent;
    });
  }

  Future<_PreparedUserContent> _buildUserContentWithFiles(
    String text,
    List<MessageImage> files,
  ) async {
    final set = _imageRecognitionSettings();
    final imageFiles = files.where((file) => file.isImage).toList();
    final textFiles = files.where(_isReadableTextAttachment).toList();
    final otherFiles = files
        .where((file) => !file.isImage && !_isReadableTextAttachment(file))
        .toList();
    final directFiles = <MessageImage>[
      if (!set.imageOcrEnabled) ...imageFiles,
      if (!set.imageRecognitionEnabled) ...otherFiles,
    ];

    final ocrText = (set.imageOcrEnabled && imageFiles.isNotEmpty)
        ? await _recognizeImagesWithOcr(imageFiles, set)
        : '';
    final fileText = (set.imageRecognitionEnabled && otherFiles.isNotEmpty)
        ? await _recognizeFilesWithModel(otherFiles, set)
        : '';
    final inlineText = textFiles.isNotEmpty
        ? await _readTextAttachments(textFiles)
        : '';

    final buffer = StringBuffer(text.trim());
    if (files.isEmpty) {
      final content = buffer.toString();
      return _PreparedUserContent(apiContent: content, textContext: content);
    }
    if (buffer.isNotEmpty) buffer.writeln('\n');
    // C: only describe files still sent as raw multimodal inputs; recognized
    // images/files are replaced by their extracted text below with a clear
    // "OCR/识别" label so the model knows it is reading recognition output
    // (possibly lossy) and not byte-for-byte source content.
    for (final file in directFiles) {
      buffer.writeln(
        '[文件: ${file.name} (${_fmtSz(file.size)}, ${file.mimeType})]',
      );
    }
    final recognizedParts = <String>[
      if (inlineText.trim().isNotEmpty) inlineText.trim(),
      if (ocrText.trim().isNotEmpty)
        '[图片 OCR 识别结果（来源: '
            '${imageFiles.map((f) => f.name).join(", ")}，可能含识别误差）]\n'
            '${ocrText.trim()}',
      if (fileText.trim().isNotEmpty)
        '[文件识别结果（来源: '
            '${otherFiles.map((f) => f.name).join(", ")}，可能含识别误差）]\n'
            '${fileText.trim()}',
    ];
    if (recognizedParts.isNotEmpty) {
      buffer.writeln(recognizedParts.join('\n'));
    }

    final textContext = buffer.toString().trim();
    return _PreparedUserContent(
      apiContent: await _directModelContent(textContext, directFiles),
      textContext: textContext,
    );
  }

  bool _isReadableTextAttachment(MessageImage file) {
    final mime = file.mimeType.toLowerCase();
    return mime.startsWith('text/') ||
        mime == 'application/json' ||
        mime == 'application/xml';
  }

  Future<String> _readTextAttachments(List<MessageImage> files) async {
    final parts = <String>[];
    for (final file in files) {
      final bytes = await File(file.path).readAsBytes();
      final content = utf8.decode(bytes, allowMalformed: true).trim();
      if (content.isEmpty) continue;
      parts.add('[文件内容: ${file.name}]\n$content');
    }
    return parts.join('\n\n');
  }

  ConversationSettings _settingsToConversationSettings() {
    final settingsProvider = context.read<SettingsProvider>();
    final settings = settingsProvider.settings;
    final model = _getModel(context.read<ModelConfigProvider>());
    return ConversationSettings(
      modelId: model?.id ?? settings.lastChatModelId ?? '',
      modelName: model?.modelName,
      thinking: _thinking,
      selectedSystemPromptId: settings.selectedSystemPromptId,
      systemPrompt: settingsProvider.effectiveSystemPrompt,
      speechModelId: settings.speechModelId,
      imageModelId: settings.imageModelId,
      imageOcrEnabled: settings.imageOcrEnabled,
      imageRecognitionModelId: settings.imageRecognitionModelId,
      imageRecognitionEnabled: settings.imageRecognitionEnabled,
      imageRecognitionPrompt: settings.imageRecognitionPrompt,
      imageGenerationModelId: settings.imageGenerationModelId,
      imageGenerationEnabled: settings.imageGenerationEnabled,
      agentEnabled: settings.agentEnabledByDefault,
    );
  }

  Future<String> _recognizeFilesWithModel(
    List<MessageImage> files,
    ConversationSettings set,
  ) async {
    return _recognition.recognizeMessageFilesWithModel(
      modelConfigs: context.read<ModelConfigProvider>(),
      settings: set,
      files: files,
    );
  }

  Future<String> _recognizeImagesWithOcr(
    List<MessageImage> files,
    ConversationSettings set,
  ) async {
    return _recognition.recognizeMessageImagesWithOcr(
      modelConfigs: context.read<ModelConfigProvider>(),
      settings: set,
      files: files,
    );
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

  // 根据配置选择系统语音识别或服务端语音转文字，启动录音流程。
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

  // 使用 record 包启动麦克风录制 AAC 音频到临时文件。
  Future<void> _startAudioRecording() async {
    final requestGen = ++_recordingRequestGen;
    _recordingStartCancelled = false;
    final hasPermission = await _audioRecorder.hasPermission();
    if (!mounted || requestGen != _recordingRequestGen) return;
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
      if (!mounted ||
          requestGen != _recordingRequestGen ||
          _recordingStartCancelled) {
        return;
      }
      await _audioRecorder.start(
        const RecordConfig(encoder: AudioEncoder.aacLc),
        path: path,
      );
      if (!mounted ||
          requestGen != _recordingRequestGen ||
          _recordingStartCancelled) {
        await _audioRecorder.stop();
        unawaited(_deleteTemporaryFile(path));
        return;
      }
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
    final requestGen = ++_recordingRequestGen;
    _recordingStartCancelled = false;
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
    if (!mounted ||
        requestGen != _recordingRequestGen ||
        _recordingStartCancelled) {
      return;
    }
    final locale = Localizations.localeOf(context);
    final localeId =
        '${locale.languageCode}_${locale.countryCode ?? locale.languageCode.toUpperCase()}';
    if (ok) {
      setState(() => _recording = true);
      try {
        if (requestGen != _recordingRequestGen || _recordingStartCancelled) {
          setState(() => _recording = false);
          return;
        }
        _speech.listen(
          onResult: (r) {
            if (!mounted || requestGen != _recordingRequestGen) return;
            _msgCtrl.text = r.recognizedWords;
            _msgCtrl.selection = TextSelection.collapsed(
              offset: _msgCtrl.text.length,
            );
            _inputRevision.value++;
            if (r.finalResult) {
              setState(() => _recording = false);
            } else {
              setState(() {});
            }
          },
          listenOptions: stt.SpeechListenOptions(localeId: localeId),
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

  // 将语音识别结果填入输入框，不直接发送消息。
  void _fillSpeechText(String txt) {
    final text = txt.trim();
    if (text.isEmpty) return;
    final current = _msgCtrl.text.trim();
    _msgCtrl.text = current.isEmpty ? text : '$current\n$text';
    _msgCtrl.selection = TextSelection.collapsed(offset: _msgCtrl.text.length);
    if (!_isMobilePlatform) _focusNode.requestFocus();
    _inputRevision.value++;
  }

  // 将录制文件通过服务端语音模型转为文字，并填入输入框。
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
      unawaited(_deleteTemporaryFile(path));
    }
  }

  Future<void> _deleteTemporaryFile(String path) async {
    try {
      await File(path).delete();
    } on FileSystemException {
      // Best-effort cleanup for recorder temp files.
    }
  }

  Future<void> _stopVoice() async {
    _recordingStartCancelled = true;
    _recordingRequestGen++;
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
    _sendGen++;
    _clearRetryState();
    _pendingModelId = null;
    _expandedThinkIds.clear();
    _thinkMap.clear();
    setState(() {
      _preparingSend = false;
      _convId = cid.isEmpty ? null : cid;
      _thinkingTxt = null;
      _thinkExpanded = false;
    });
    if (cid.isNotEmpty) {
      _applyConversationSettings(cid);
    }
    _closeSearch();
    _scheduleJumpToBottom(unfocusInput: true, waitForStableLayout: true);
    Navigator.pop(context);
  }

  void _rememberHistoryScrollOffset() {
    if (!_historyScrollController.hasClients) return;
    final position = _historyScrollController.position;
    if (!position.hasContentDimensions) return;
    _historyScrollOffset = position.pixels
        .clamp(position.minScrollExtent, position.maxScrollExtent)
        .toDouble();
  }

  void _scheduleHistoryScrollRestore() {
    final generation = ++_historyScrollRestoreGeneration;
    _restoreHistoryScrollOffset(generation, 4);
  }

  void _restoreHistoryScrollOffset(int generation, int attemptsLeft) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _historyScrollRestoreGeneration) return;
      if (!_historyScrollController.hasClients ||
          !_historyScrollController.position.hasContentDimensions) {
        if (attemptsLeft > 1) {
          _restoreHistoryScrollOffset(generation, attemptsLeft - 1);
        }
        return;
      }
      final position = _historyScrollController.position;
      final target = _historyScrollOffset
          .clamp(position.minScrollExtent, position.maxScrollExtent)
          .toDouble();
      _historyScrollOffset = target;
      if ((position.pixels - target).abs() > 0.5) {
        _historyScrollController.jumpTo(target);
      }
    });
  }

  void _toggleHistoryRole(String roleId) {
    setState(() {
      if (!_collapsedHistoryRoleIds.add(roleId)) {
        _collapsedHistoryRoleIds.remove(roleId);
      }
    });
  }

  void _startNewConversation() {
    // Bottom-nav double tap and the app-bar action both route here. Keep all
    // transient chat modes in one place so a new chat cannot inherit selection,
    // streaming, retry, or pending-send state from the previous conversation.
    if (_shareSelecting) _cancelShareSelection();
    if (_streaming) _stopStreaming();
    _sendGen++;
    _clearRetryState();
    _clearPendingState();
    final defaults = context.read<SettingsProvider>().settings;
    setState(() {
      _preparingSend = false;
      _convId = null;
      _agentEnabled = defaults.agentEnabledByDefault;
      _draftSettings = null;
    });
    _closeSearch();
    _scheduleJumpToBottom(unfocusInput: true);
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
      builder: (ctx) => DialogSettingsContent(
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
      canPop: !_shareSelecting && !_showSearch,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_showSearch) {
          _closeSearch();
        } else if (_shareSelecting) {
          _cancelShareSelection();
        }
      },
      child: Scaffold(
        onDrawerChanged: (opened) {
          if (opened) {
            _scheduleHistoryScrollRestore();
          } else {
            _rememberHistoryScrollOffset();
          }
        },
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
            else ...[
              IconButton(
                icon: const Icon(Icons.search),
                tooltip: '搜索当前对话',
                onPressed: conv == null || conv.messages.isEmpty
                    ? null
                    : _openSearch,
              ),
              if (_convId != null)
                IconButton(
                  icon: const Icon(Icons.add_comment_outlined),
                  tooltip: '新建对话',
                  onPressed: _startNewConversation,
                ),
            ],
          ],
        ),
        drawer: _shareSelecting ? null : _drawer(context),
        body: _body(conv, model, mp),
      ),
    );
  }

  Widget _drawer(BuildContext ctx) => Drawer(
    child: HistoryDrawer(
      onSelect: _selectHistory,
      currentConvId: _convId,
      scrollController: _historyScrollController,
      collapsedRoleIds: Set.unmodifiable(_collapsedHistoryRoleIds),
      onToggleRole: _toggleHistoryRole,
    ),
  );

  Widget _body(Conversation? conv, ModelConfig? model, ModelConfigProvider mp) {
    final msgs = conv != null ? conv.messages.toList() : <Message>[];
    _pruneMessageKeys(msgs);
    if (_showSearch) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshSearchMatches();
      });
    }
    int lastUserIdx = -1;
    for (int i = msgs.length - 1; i >= 0; i--) {
      if (msgs[i].role == 'user') {
        lastUserIdx = i;
        break;
      }
    }
    return Column(
      children: [
        if (_showSearch) _searchBar(),
        Expanded(
          child: Stack(
            children: [
              msgs.isEmpty
                  ? _empty()
                  : NotificationListener<ScrollNotification>(
                      onNotification: _onScrollNotification,
                      child: SystemScrollCaptureTarget(
                        controller: _scrollCtrl,
                        enabled: widget.active && !_shareSelecting,
                        child: ListView.builder(
                          controller: _scrollCtrl,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 8,
                          ),
                          itemCount: msgs.length,
                          itemBuilder: (_, i) {
                            final msg = msgs[i];
                            return KeyedSubtree(
                              key: _messageKeyFor(msg.id),
                              child: _selectableBubble(
                                msg,
                                i == msgs.length - 1,
                                i == lastUserIdx,
                              ),
                            );
                          },
                        ),
                      ),
                    ),
              if (_showScrollToBottom) _scrollToBottomButton(),
              if (_showModelMenu) _floatingModelList(mp),
              if (_showCommandPalette) _floatingCommandPalette(),
            ],
          ),
        ),
        if (conv?.agentPlan != null) _agentPlanPanel(conv!.agentPlan!),
        _inputArea(model, mp),
      ],
    );
  }

  Widget _searchBar() {
    final scheme = Theme.of(context).colorScheme;
    final hasSearchError = _searchRegexError != null;
    final matchText = hasSearchError
        ? '正则错误'
        : _searchCtrl.text.trim().isEmpty
        ? '输入关键词'
        : _searchMatches.isEmpty
        ? '无匹配'
        : '${_currentSearchMatch + 1}/${_searchMatches.length}';
    return Material(
      color: scheme.surfaceContainerHighest,
      child: SafeArea(
        top: false,
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 8),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocusNode,
                  decoration: InputDecoration(
                    isDense: true,
                    hintText: '搜索当前对话，支持 re:正则 或 /正则/i',
                    prefixIcon: const Icon(Icons.search),
                    suffixText: matchText,
                    errorText: hasSearchError ? _searchRegexError : null,
                    border: const OutlineInputBorder(),
                  ),
                  textInputAction: TextInputAction.search,
                  onSubmitted: (_) => _nextSearchMatch(),
                ),
              ),
              IconButton(
                tooltip: '上一个',
                icon: const Icon(Icons.keyboard_arrow_up),
                onPressed: _searchMatches.isEmpty ? null : _previousSearchMatch,
              ),
              IconButton(
                tooltip: '下一个',
                icon: const Icon(Icons.keyboard_arrow_down),
                onPressed: _searchMatches.isEmpty ? null : _nextSearchMatch,
              ),
              IconButton(
                tooltip: '关闭',
                icon: const Icon(Icons.close),
                onPressed: _closeSearch,
              ),
            ],
          ),
        ),
      ),
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

  Widget _agentPlanPanel(AgentPlan plan) {
    final scheme = Theme.of(context).colorScheme;
    final narrow = MediaQuery.of(context).size.width < 600;
    final expanded = _agentPlanExpanded ?? !narrow;
    final completed = plan.items
        .where(
          (item) =>
              item.status == AgentPlanItem.completed ||
              item.status == AgentPlanItem.skipped,
        )
        .length;
    AgentPlanItem? active;
    for (final item in plan.items) {
      if (item.status == AgentPlanItem.inProgress ||
          item.status == AgentPlanItem.needsConfirmation ||
          item.status == AgentPlanItem.failed) {
        active = item;
        break;
      }
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 4, 14, 2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _agentPlanExpanded = !expanded),
            borderRadius: BorderRadius.circular(8),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  Icon(
                    expanded ? Icons.expand_more : Icons.chevron_right,
                    size: 18,
                    color: scheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 2),
                  Expanded(
                    child: Text(
                      active == null
                          ? '计划 $completed/${plan.items.length}：${plan.title}'
                          : '计划 $completed/${plan.items.length}：${active.title}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          if (expanded) ...[
            const SizedBox(height: 2),
            for (final item in plan.items)
              Padding(
                padding: const EdgeInsets.only(left: 20),
                child: _agentPlanStep(item),
              ),
          ],
          Divider(
            height: 8,
            color: scheme.outlineVariant.withValues(alpha: 0.25),
          ),
        ],
      ),
    );
  }

  Widget _agentPlanStep(AgentPlanItem item) {
    final scheme = Theme.of(context).colorScheme;
    final active =
        item.status == AgentPlanItem.inProgress ||
        item.status == AgentPlanItem.needsConfirmation;
    final failed = item.status == AgentPlanItem.failed;
    final completed =
        item.status == AgentPlanItem.completed ||
        item.status == AgentPlanItem.skipped;
    final detail = failed
        ? (item.error ?? item.summary)
        : completed
        ? (item.resultSummary ?? item.summary)
        : item.summary;
    final color = failed
        ? scheme.error
        : active
        ? scheme.primary
        : scheme.onSurfaceVariant.withValues(alpha: completed ? 0.58 : 0.82);
    final marker = completed
        ? '✓'
        : failed
        ? '!'
        : active
        ? '•'
        : '·';
    return Padding(
      padding: const EdgeInsets.only(top: 3),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 16,
            child: Text(
              marker,
              textAlign: TextAlign.center,
              style: TextStyle(color: color, fontSize: 12),
            ),
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 12,
                    color: color,
                    fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                  ),
                ),
                if (detail != null && detail.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 1),
                    child: Text(
                      detail,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 11,
                        color: failed
                            ? scheme.error
                            : scheme.onSurfaceVariant.withValues(alpha: 0.68),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _empty() => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.chat_bubble_outline,
          size: 80,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        const SizedBox(height: 16),
        Text(
          '开始新对话',
          style: TextStyle(
            fontSize: 20,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w300,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          '在下方输入你的问题',
          style: TextStyle(
            fontSize: 14,
            color: Theme.of(context).colorScheme.outline,
          ),
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
                    : Theme.of(context).colorScheme.outline,
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
      final hasSearchMatch = _showSearch && _messageHasSearchMatch(msg.id);
      final currentSearchMessage = _isCurrentSearchMessage(msg.id);
      final scheme = Theme.of(context).colorScheme;
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
                      color: currentSearchMessage
                          ? scheme.primaryContainer
                          : hasSearchMatch
                          ? scheme.secondaryContainer.withValues(alpha: 0.42)
                          : scheme.primaryContainer,
                      borderRadius: const BorderRadius.only(
                        topLeft: Radius.circular(16),
                        topRight: Radius.circular(16),
                        bottomLeft: Radius.circular(16),
                      ),
                      border: hasSearchMatch
                          ? Border.all(
                              color: currentSearchMessage
                                  ? scheme.primary
                                  : scheme.secondary.withValues(alpha: 0.7),
                              width: currentSearchMessage ? 1.6 : 1,
                            )
                          : null,
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
                        if (msg.content.isNotEmpty) _searchableUserText(msg),
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
                        color: Theme.of(context).colorScheme.outline,
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
    if (isLastAi && _streaming && _streamingConvId == _convId) {
      return ValueListenableBuilder<_StreamDraft>(
        valueListenable: _streamDraft,
        builder: (context, draft, _) => _assistantBubble(msg, true, draft),
      );
    }
    return _assistantBubble(msg, isLastAi, null);
  }

  Widget _assistantBubble(Message msg, bool isLastAi, _StreamDraft? draft) {
    final streaming = draft != null;
    final displayContent = streaming ? draft.content : msg.content;
    final knowledge = context.read<KnowledgeProvider>();
    final fallbackKnowledgeCategory =
        knowledge.annotationFallbackCategory?.alias;
    final showImages = msg.images.isNotEmpty;
    final hasSearchMatch = _showSearch && _messageHasSearchMatch(msg.id);
    final currentSearchMessage = _isCurrentSearchMessage(msg.id);
    final scheme = Theme.of(context).colorScheme;
    final draftThink = draft?.thinking;
    final thinkForMsg = isLastAi
        ? (draftThink != null && draftThink.isNotEmpty
              ? draftThink
              : (_thinkingTxt != null && _thinkingTxt!.isNotEmpty
                    ? _thinkingTxt
                    : _thinkForMessage(msg)))
        : _thinkForMessage(msg);
    final missingThinkNotice = _missingThinkNotice(msg, isLastAi);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (isLastAi && thinkForMsg != null && thinkForMsg.isNotEmpty)
          _thinkSection(thinkForMsg),
        if (isLastAi && thinkForMsg == null && missingThinkNotice != null)
          _thinkSection(missingThinkNotice),
        if (isLastAi && draft?.status != null) _streamStatus(draft!.status!),
        if (!isLastAi) ..._buildPerMsgThinkSection(msg),
        if (msg.agentTrace != null && msg.agentTrace!.events.isNotEmpty)
          _agentTracePanel(msg.agentTrace!),
        if (streaming && draft.activeSkillDisplayName != null)
          _skillLoadingLabel(draft.activeSkillDisplayName!),
        if (streaming &&
            draft.activeToolName != null &&
            draft.activeSkillDisplayName == null)
          _toolCallBadge(draft.activeToolName!),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: BoxConstraints(maxWidth: _assistantContentMaxWidth()),
          decoration: BoxDecoration(
            color: currentSearchMessage
                ? scheme.primaryContainer.withValues(alpha: 0.72)
                : hasSearchMatch
                ? scheme.tertiaryContainer.withValues(alpha: 0.32)
                : scheme.surfaceContainerHighest,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomRight: Radius.circular(16),
            ),
            border: hasSearchMatch
                ? Border.all(
                    color: currentSearchMessage
                        ? scheme.primary
                        : scheme.tertiary.withValues(alpha: 0.65),
                    width: currentSearchMessage ? 1.6 : 1,
                  )
                : null,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.03),
                blurRadius: 3,
                offset: const Offset(0, 1),
              ),
            ],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (displayContent.isNotEmpty)
                MarkdownWithLatex(
                  content: displayContent,
                  renderMermaid: !streaming,
                  fallbackKnowledgeCategory: fallbackKnowledgeCategory,
                  knowledgeCategoryResolver:
                      knowledge.resolveAnnotationCategory,
                  knowledgeCategoryColorResolver: (id) {
                    final category = knowledge.categoryById(id);
                    return category == null || category.colorValue == 0
                        ? null
                        : Color(category.colorValue);
                  },
                  onTapKnowledgeAnnotation: streaming
                      ? null
                      : (annotation) => _showKnowledgeExplanation(
                          text: annotation.text,
                          message: msg,
                          categoryId: annotation.category,
                        ),
                  onExplainSelection: streaming
                      ? null
                      : (text) => _showKnowledgeExplanation(
                          text: text,
                          message: msg,
                          saveAutomatically: false,
                        ),
                  onTapLink: (_, href, _) {
                    if (href != null) _openExternalLink(href);
                  },
                ),
              if (showImages && displayContent.isNotEmpty)
                const SizedBox(height: 8),
              if (showImages) _messageImages(msg.images),
              if (displayContent.isEmpty && streaming) ...[
                if (showImages) const SizedBox(height: 8),
                const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ],
            ],
          ),
        ),
        if (!streaming && !_shareSelecting) _bubbleActions(msg, isLastAi),
      ],
    );
  }

  Widget _agentTracePanel(AgentTrace trace) {
    final scheme = Theme.of(context).colorScheme;
    const maxVisibleEvents = 30;
    final errors = trace.events
        .where((event) => event.type == AgentTraceEvent.error)
        .length;
    final last = trace.events.last;
    final visibleEvents = trace.events.length > maxVisibleEvents
        ? trace.events.sublist(trace.events.length - maxVisibleEvents)
        : trace.events;
    final hiddenCount = trace.events.length - visibleEvents.length;
    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      constraints: BoxConstraints(maxWidth: _assistantContentMaxWidth()),
      child: Material(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.55),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.7)),
        ),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            tilePadding: const EdgeInsets.symmetric(horizontal: 12),
            childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            initiallyExpanded: false,
            leading: Icon(
              Icons.route_outlined,
              size: 18,
              color: scheme.primary,
            ),
            title: Text(
              'Agent 过程 · ${trace.events.length} 步${errors > 0 ? ' · $errors 个错误' : ''}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
            subtitle: Text(
              last.content == null || last.content!.isEmpty
                  ? last.title
                  : '${last.title}：${last.content}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
            ),
            children: [
              if (hiddenCount > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    '已省略较早的 $hiddenCount 步',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
                ),
              for (final event in visibleEvents) _agentTraceEventRow(event),
            ],
          ),
        ),
      ),
    );
  }

  Widget _agentTraceEventRow(AgentTraceEvent event) {
    final scheme = Theme.of(context).colorScheme;
    final (icon, color) = switch (event.type) {
      AgentTraceEvent.toolCall => (Icons.play_arrow_rounded, scheme.tertiary),
      AgentTraceEvent.toolResult => (
        Icons.check_circle_outline,
        scheme.primary,
      ),
      AgentTraceEvent.planUpdate => (
        Icons.account_tree_outlined,
        scheme.secondary,
      ),
      AgentTraceEvent.memoryUpdate => (Icons.psychology_alt, scheme.primary),
      AgentTraceEvent.error => (Icons.error_outline, scheme.error),
      _ => (Icons.notes_outlined, scheme.onSurfaceVariant),
    };
    final label = switch (event.type) {
      AgentTraceEvent.toolCall => '工具调用',
      AgentTraceEvent.toolResult => '工具结果',
      AgentTraceEvent.planUpdate => '计划更新',
      AgentTraceEvent.memoryUpdate => '记忆更新',
      AgentTraceEvent.error => '错误',
      _ => '中间说明',
    };
    final content = event.content == null
        ? null
        : _compactAgentTraceText(event.content!, maxLength: 240);
    final traceImages = _agentTraceImages(event);
    final displayMetadata = event.metadata == null
        ? null
        : (Map<String, dynamic>.from(event.metadata!)..remove('images'));
    final metadata = displayMetadata == null || displayMetadata.isEmpty
        ? null
        : _compactAgentTraceText(jsonEncode(displayMetadata), maxLength: 320);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        event.title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 1,
                      ),
                      decoration: BoxDecoration(
                        color: color.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(999),
                      ),
                      child: Text(
                        label,
                        style: TextStyle(fontSize: 10, color: color),
                      ),
                    ),
                  ],
                ),
                if (content != null && content.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      content,
                      style: TextStyle(
                        fontSize: 12,
                        color: scheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                if (metadata != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      metadata,
                      style: TextStyle(
                        fontSize: 11,
                        color: scheme.onSurfaceVariant.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                if (traceImages.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: _messageImages(traceImages),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<MessageImage> _agentTraceImages(AgentTraceEvent event) {
    final rawImages = event.metadata?['images'];
    if (rawImages is! List) return const [];
    return rawImages
        .whereType<Map>()
        .map((item) => MessageImage.fromJson(Map<String, dynamic>.from(item)))
        .where((image) => image.path.isNotEmpty && image.isImage)
        .toList(growable: false);
  }

  String _compactAgentTraceText(String value, {required int maxLength}) {
    final singleLine = value.replaceAll(RegExp(r'\s+'), ' ').trim();
    if (singleLine.length <= maxLength) return singleLine;
    return '${singleLine.substring(0, maxLength)}...';
  }

  Widget _messageImages(List<MessageImage> images) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: images.map((image) {
        final exists = _attachmentExists(image.path);
        if (!image.isImage) {
          return _fileChip(image, exists: exists);
        }
        return InkWell(
          onTap: exists
              ? () => _showAttachmentImagePreview(images, image)
              : null,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(10),
            child: exists
                ? Image.file(
                    File(image.path),
                    width: 120,
                    height: 120,
                    cacheWidth: _imageCacheExtent(120),
                    cacheHeight: _imageCacheExtent(120),
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

  bool _attachmentExists(String path) {
    return _attachmentExistsCache.putIfAbsent(path, () {
      return path.isNotEmpty && File(path).existsSync();
    });
  }

  int _imageCacheExtent(double logicalSize) {
    return (logicalSize * MediaQuery.devicePixelRatioOf(context)).round();
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

  Future<void> _sharePreviewImage(String path, String name) async {
    try {
      final file = File(path);
      if (!await file.exists()) {
        if (mounted) _showShareImageSnack('图片文件已不存在');
        return;
      }
      await SharePlus.instance.share(
        ShareParams(files: [XFile(path)], text: name.isEmpty ? null : name),
      );
    } catch (e) {
      if (mounted) _showShareImageSnack('分享失败: $e');
    }
  }

  Future<void> _copyPreviewImageToClipboard(MessageImage image) async {
    try {
      final clipboard = SystemClipboard.instance;
      if (clipboard == null) throw Exception('当前平台不支持写入剪贴板');
      final file = File(image.path);
      if (!await file.exists()) {
        if (mounted) _showShareImageSnack('图片文件已不存在');
        return;
      }
      final item = DataWriterItem(suggestedName: image.name);
      final bytes = await file.readAsBytes();
      switch (image.mimeType) {
        case 'image/jpeg':
          item.add(Formats.jpeg(bytes));
        case 'image/webp':
          item.add(Formats.webp(bytes));
        case 'image/gif':
          item.add(Formats.gif(bytes));
        default:
          item.add(Formats.png(bytes));
      }
      await clipboard.write([item]);
      if (mounted) _showShareImageSnack('图片已复制到剪贴板');
    } catch (e) {
      if (mounted) _showShareImageSnack('复制失败: $e');
    }
  }

  void _showAttachmentImagePreview(
    List<MessageImage> attachments,
    MessageImage selected,
  ) {
    final images = attachments
        .where((item) => item.isImage && _attachmentExists(item.path))
        .toList(growable: false);
    if (images.isEmpty) return;
    final index = images.indexWhere(
      (item) => item.path == selected.path && item.name == selected.name,
    );
    _showImagePreview(images, initialIndex: index < 0 ? 0 : index);
  }

  void _showImagePreview(List<MessageImage> images, {int initialIndex = 0}) {
    if (images.isEmpty) return;
    var index = initialIndex.clamp(0, images.length - 1).toInt();
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) {
          void showPrevious() {
            setDialogState(
              () => index = index == 0 ? images.length - 1 : index - 1,
            );
          }

          void showNext() {
            setDialogState(
              () => index = index == images.length - 1 ? 0 : index + 1,
            );
          }

          return Dialog(
            insetPadding: const EdgeInsets.all(12),
            backgroundColor: Colors.black,
            child: Stack(
              children: [
                Positioned.fill(
                  child: InteractiveViewer(
                    child: Center(
                      child: Image.file(
                        File(images[index].path),
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                ),
                if (images.length > 1) ...[
                  Positioned(
                    left: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filledTonal(
                        onPressed: showPrevious,
                        icon: const Icon(Icons.chevron_left),
                        tooltip: '上一张',
                      ),
                    ),
                  ),
                  Positioned(
                    right: 8,
                    top: 0,
                    bottom: 0,
                    child: Center(
                      child: IconButton.filledTonal(
                        onPressed: showNext,
                        icon: const Icon(Icons.chevron_right),
                        tooltip: '下一张',
                      ),
                    ),
                  ),
                ],
                Positioned(
                  left: 12,
                  right: 72,
                  bottom: 12,
                  child: DecoratedBox(
                    decoration: const BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.all(Radius.circular(12)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      child: Text(
                        images.length == 1
                            ? images[index].name
                            : '${index + 1}/${images.length} · ${images[index].name}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 8,
                  top: 8,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      PopupMenuButton<_PreviewImageAction>(
                        tooltip: '图片菜单',
                        icon: const Icon(Icons.more_vert, color: Colors.white),
                        color: Theme.of(context).colorScheme.surface,
                        onSelected: (action) {
                          final image = images[index];
                          switch (action) {
                            case _PreviewImageAction.save:
                              unawaited(
                                _savePreviewImageToGallery(
                                  image.path,
                                  image.name,
                                ),
                              );
                            case _PreviewImageAction.copyImage:
                              unawaited(_copyPreviewImageToClipboard(image));
                            case _PreviewImageAction.share:
                              unawaited(
                                _sharePreviewImage(image.path, image.name),
                              );
                            case _PreviewImageAction.close:
                              Navigator.pop(ctx);
                          }
                        },
                        itemBuilder: (context) => const [
                          PopupMenuItem(
                            value: _PreviewImageAction.save,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.save_alt_outlined),
                              title: Text('保存到相册'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _PreviewImageAction.copyImage,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.copy_outlined),
                              title: Text('复制图片'),
                            ),
                          ),
                          PopupMenuItem(
                            value: _PreviewImageAction.share,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.ios_share_outlined),
                              title: Text('分享图片'),
                            ),
                          ),
                          PopupMenuDivider(),
                          PopupMenuItem(
                            value: _PreviewImageAction.close,
                            child: ListTile(
                              dense: true,
                              leading: Icon(Icons.close),
                              title: Text('关闭'),
                            ),
                          ),
                        ],
                      ),
                      IconButton(
                        onPressed: () => Navigator.pop(ctx),
                        icon: const Icon(Icons.close, color: Colors.white),
                        tooltip: '关闭',
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
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
                    color: Theme.of(context).colorScheme.outline,
                  ),
                  const SizedBox(width: 4),
                  Text(
                    '思考过程',
                    style: TextStyle(
                      fontSize: 11,
                      color: Theme.of(context).colorScheme.outline,
                    ),
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
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                  height: 1.4,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _streamStatus(String text) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
      child: Text(
        text,
        style: TextStyle(fontSize: 12, color: scheme.onSurfaceVariant),
      ),
    );
  }

  Widget _skillLoadingLabel(String name) {
    final scheme = Theme.of(context).colorScheme;
    return ConstrainedBox(
      constraints: BoxConstraints(maxWidth: _assistantContentMaxWidth()),
      child: Container(
        width: double.infinity,
        margin: const EdgeInsets.only(top: 2, bottom: 4),
        alignment: Alignment.center,
        child: Text(
          '加载SKILL：$name',
          textAlign: TextAlign.center,
          style: TextStyle(
            fontSize: 12,
            color: scheme.onSurfaceVariant.withValues(alpha: 0.72),
          ),
        ),
      ),
    );
  }

  Widget _toolCallBadge(String toolName) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '*',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: Colors.amber.shade700,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            toolName,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: Colors.amber.shade700,
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
                      color: Theme.of(context).colorScheme.outline,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '思考过程',
                      style: TextStyle(
                        fontSize: 11,
                        color: Theme.of(context).colorScheme.outline,
                      ),
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
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
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
      child: Icon(i, size: 16, color: Theme.of(context).colorScheme.outline),
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
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.15),
                ),
              ),
            ),
          ),
          Text(
            '${current + 1}/$total',
            style: TextStyle(
              fontSize: 11,
              color: Theme.of(context).colorScheme.outline,
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
                      : Theme.of(
                          context,
                        ).colorScheme.onSurface.withValues(alpha: 0.15),
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
    if (entry.hasAssistantSnapshot) {
      if (lastAssistant.isNotEmpty) {
        cp.updateMessageContent(
          _convId!,
          lastAssistant.last.id,
          entry.assistantContent ?? '',
          thinkingContent: entry.thinkingContent,
        );
        cp.updateMessageImages(
          _convId!,
          lastAssistant.last.id,
          entry.assistantImages,
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
          entry.assistantContent ?? '',
          images: entry.assistantImages,
          thinkingContent: entry.thinkingContent,
        );
      }
      _thinkingTxt = entry.thinkingContent;
    } else {
      if (lastAssistant.isNotEmpty) {
        cp.updateMessageContent(
          _convId!,
          lastAssistant.last.id,
          '',
          thinkingContent: null,
        );
        cp.updateMessageImages(_convId!, lastAssistant.last.id, const []);
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
          autofocus: !_isMobilePlatform,
        ),
        actions: [
          TextButton(
            onPressed: () async {
              if (!isLastUserMsg && !await _confirmWithdrawHistorical(ctx)) {
                return;
              }
              if (!ctx.mounted) return;
              Navigator.pop(ctx);
              if (mounted) _withdrawMessage(msg);
            },
            child: Text(isLastUserMsg ? '撤回' : '撤回并删除后续'),
          ),
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

  Future<bool> _confirmWithdrawHistorical(BuildContext dialogContext) async {
    final result = await showDialog<bool>(
      context: dialogContext,
      builder: (ctx) => AlertDialog(
        title: const Text('撤回历史消息'),
        content: const Text('撤回这条消息会删除它之后的所有对话内容，并把原消息放回输入框。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('撤回'),
          ),
        ],
      ),
    );
    return result == true;
  }

  void _withdrawMessage(Message msg) {
    final cid = _convId;
    if (cid == null) return;
    final conv = context.read<ConversationProvider>().getConversation(cid);
    if (conv == null || !conv.messages.any((m) => m.id == msg.id)) return;
    // Withdrawal is a branch reset: the selected user message goes back to the
    // composer and every later message is discarded so the context stays valid.
    if (_shareSelecting) _cancelShareSelection();
    if (_streaming) _stopStreaming();
    _sendGen++;
    _clearRetryState();
    _pendingModelId = null;
    _thinkingTxt = null;
    _thinkExpanded = false;
    _expandedThinkIds.clear();
    _thinkMap.clear();
    _updateStreamDraft(const _StreamDraft());
    if (msg.composerSegments.isNotEmpty) {
      _msgCtrl.replaceSegments(msg.composerSegments);
    } else {
      _msgCtrl.text = msg.content;
    }
    _msgCtrl.selection = TextSelection.collapsed(offset: _msgCtrl.text.length);
    _inputRevision.value++;
    setState(() {
      _preparingSend = false;
      _pendingImages
        ..clear()
        ..addAll(msg.images.map(_pendingImageFromMessageImage));
    });
    context.read<ConversationProvider>().deleteMessagesFrom(cid, msg.id);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && !_isMobilePlatform) _focusNode.requestFocus();
    });
  }

  _PendingImage _pendingImageFromMessageImage(MessageImage image) {
    return _PendingImage(
      path: image.path,
      name: image.name,
      size: image.size,
      mimeType: image.mimeType,
    );
  }

  Future<void> _editStartNewConversation(
    Message origMsg,
    String newText,
  ) async {
    final sourceCid = _convId;
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    final editModel = _getModel(mp);
    if (editModel == null || sourceCid == null) {
      if (editModel == null) _showMissingChatModelTip();
      return;
    }
    final origConv = cp.getConversation(sourceCid);
    if (origConv == null) return;
    final allMsgs = origConv.messages;
    final origMsgIdx = allMsgs.indexWhere((m) => m.id == origMsg.id);
    if (origMsgIdx == -1) return;
    final sendGen = ++_sendGen;
    final preparedUserContent = await _prepareUserContent(
      newText,
      origMsg.images,
    );
    if (!mounted || preparedUserContent == null) return;
    if (sendGen != _sendGen || _convId != sourceCid) return;
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
        modelContextContent: allMsgs[i].modelContextContent,
        images: allMsgs[i].images,
        thinkingContent: allMsgs[i].thinkingContent,
      );
    }
    cp.addMessage(
      newConvId,
      'user',
      newText,
      modelContextContent: preparedUserContent.textContext,
      images: origMsg.images,
    );
    setState(() {
      _convId = newConvId;
      _clearPendingState();
      _beginStreaming(newConvId);
    });
    _scrollEnd();
    cp.addMessage(newConvId, 'assistant', '', save: false);
    await WidgetsBinding.instance.endOfFrame;
    if (!mounted) return;
    if (!_streaming || _convId != newConvId || sendGen != _sendGen) {
      _clearAbortedStreaming('编辑消息新建对话后状态已失效', conversationId: newConvId);
      return;
    }
    _doSend(editModel, lastUserContentOverride: preparedUserContent.apiContent);
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
                    : ChatComposerKeyboard(
                        controller: _msgCtrl,
                        onSend: () => unawaited(_send()),
                        onPaste: () => unawaited(_handlePasteShortcut()),
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
                          onTap: _handleInputTap,
                          onChanged: (_) => _inputRevision.value++,
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
              _commandBtn(),
              const SizedBox(width: 4),
              _dialogSetBtn(),
              const SizedBox(width: 4),
              _agentBtn(),
              const SizedBox(width: 4),
              _thinkBtn(),
              const SizedBox(width: 4),
              _ocrBtn(),
              const SizedBox(width: 4),
              _imageRecognitionBtn(),
              const SizedBox(width: 4),
              _imageGenerationBtn(),
              const Spacer(),
              _attachBtn(),
              const SizedBox(width: 4),
              ValueListenableBuilder<int>(
                valueListenable: _inputRevision,
                builder: (context, _, _) => _voiceOrSendBtn(hasSpeech),
              ),
            ],
          ),
          if (_showAttach) _attachMenu(),
        ],
      ),
    );
  }

  Widget _modelList(ModelConfigProvider mp) {
    final cur = _getModel(mp);
    final models = mp.enabledModelsByCategory(ModelConfig.categoryChat);
    final settings = _activeSettings();
    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(10),
      clipBehavior: Clip.antiAlias,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxHeight: 260),
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
                              : Theme.of(context).colorScheme.outline,
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
                                      : Theme.of(context).colorScheme.outline,
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
                _showImageRecognitionList
                    ? Icons.expand_less
                    : Icons.expand_more,
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
                        : Theme.of(context).colorScheme.outline,
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
            const Divider(height: 1),
            ListTile(
              dense: true,
              leading: Icon(
                Icons.auto_awesome,
                size: 18,
                color: Theme.of(context).colorScheme.primary,
              ),
              title: const Text('图片生成', style: TextStyle(fontSize: 14)),
              subtitle: const Text('选择图片生成模型', style: TextStyle(fontSize: 11)),
              trailing: Icon(
                _showImageGenerationList
                    ? Icons.expand_less
                    : Icons.expand_more,
                size: 16,
              ),
              onTap: () {
                setState(() {
                  _showImageGenerationList = !_showImageGenerationList;
                });
              },
            ),
            if (_showImageGenerationList)
              for (final m
                  in context
                      .read<ModelConfigProvider>()
                      .enabledModelsByCategory(
                        ModelConfig.categoryImageGeneration,
                      ))
                ListTile(
                  dense: true,
                  contentPadding: const EdgeInsets.only(left: 56),
                  leading: Icon(
                    settings?.imageGenerationModelId == m.id
                        ? Icons.radio_button_checked
                        : Icons.radio_button_off,
                    size: 14,
                    color: settings?.imageGenerationModelId == m.id
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.outline,
                  ),
                  title: Text(
                    m.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 13),
                  ),
                  subtitle: Text(
                    m.hasMultipleModels
                        ? '${m.enabledModelNames.length} 个模型'
                        : m.modelName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 11),
                  ),
                  onTap: () {
                    final base = _currentConversationSettings(cur ?? m);
                    _saveConversationSettings(
                      base.copyWith(imageGenerationModelId: m.id),
                    );
                    setState(() => _showImageGenerationList = false);
                  },
                ),
          ],
        ),
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

  Widget _floatingCommandPalette() {
    return Positioned(
      left: 12,
      right: 12,
      bottom: 8,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(12),
        color: Colors.transparent,
        child: ChatCommandPalette(
          registry: _selectorRegistryOf(),
          onSelected: _insertComposerReference,
        ),
      ),
    );
  }

  Widget _commandBtn() {
    final scheme = Theme.of(context).colorScheme;
    final active = _showCommandPalette;
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: () => setState(() {
        _showCommandPalette = !_showCommandPalette;
        if (_showCommandPalette) _showModelMenu = false;
      }),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: active ? scheme.primary.withValues(alpha: 0.1) : null,
          border: Border.all(
            color: active
                ? scheme.primary.withValues(alpha: 0.3)
                : scheme.outlineVariant,
          ),
        ),
        child: Icon(
          Icons.tag,
          size: 16,
          color: active ? scheme.primary : scheme.outline,
        ),
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

  ModelConfig? _imageGenerationModel([ConversationSettings? settings]) {
    final models = context.read<ModelConfigProvider>().enabledModelsByCategory(
      ModelConfig.categoryImageGeneration,
    );
    if (models.isEmpty) return null;
    final modelId =
        settings?.imageGenerationModelId ??
        _activeSettings()?.imageGenerationModelId ??
        context.read<SettingsProvider>().settings.imageGenerationModelId;
    if (modelId != null && modelId.isNotEmpty) {
      for (final model in models) {
        if (model.id == modelId) return model;
      }
    }
    return models.first;
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
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
        child: Icon(
          Icons.smart_toy,
          size: 18,
          color: Theme.of(context).colorScheme.outline,
        ),
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
      onTap: () => setState(() {
        _showModelMenu = true;
        _showCommandPalette = false;
      }),
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
    if (!isDesktopPlatform) return;
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
        ? scheme.onSurface.withValues(alpha: 0.15)
        : selected
        ? scheme.primary
        : scheme.outline;
    final child = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 32),
      padding: EdgeInsets.symmetric(horizontal: expanded ? 9 : 8, vertical: 6),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: selected
              ? scheme.primary
              : scheme.outlineVariant.withValues(alpha: 0.3),
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
        if (isDesktopPlatform) _expandInputAction(id);
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

  Widget _agentBtn() {
    final enabled = _activeSettings()?.agentEnabled ?? _agentEnabled;
    return _inputActionButton(
      id: 'agent',
      icon: enabled ? Icons.account_tree : Icons.account_tree_outlined,
      label: 'Agent',
      selected: enabled,
      onPressed: () {
        final value = !enabled;
        setState(() => _agentEnabled = value);
        final model = _getModel(context.read<ModelConfigProvider>());
        if (model == null) return;
        final settings = _currentConversationSettings(
          model,
        ).copyWith(agentEnabled: value);
        _saveConversationSettings(settings);
      },
    );
  }

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

  Widget _imageGenerationBtn() {
    final enabled =
        _activeSettings()?.imageGenerationEnabled ??
        context.watch<SettingsProvider>().settings.imageGenerationEnabled;
    final hasModel = _imageGenerationModel() != null;
    return _inputActionButton(
      id: 'imageGeneration',
      icon: Icons.auto_awesome,
      label: '生图',
      selected: enabled && hasModel,
      onPressed: hasModel
          ? () {
              final value = !enabled;
              final model = _getModel(context.read<ModelConfigProvider>());
              if (model == null) return;
              final imageModel = _imageGenerationModel();
              final settings = _currentConversationSettings(model).copyWith(
                imageGenerationEnabled: value,
                imageGenerationModelId: imageModel?.id,
              );
              setState(() {});
              _saveConversationSettings(settings);
            }
          : null,
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
            : Theme.of(context).colorScheme.outline,
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
        if (!isDesktopPlatform) ...[
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
          Icon(
            i,
            size: 16,
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text(
            l,
            style: TextStyle(
              fontSize: 12,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
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
                    ? () => _showAttachmentImagePreview(
                        _pendingImages
                            .map((item) => item.toMessageImage())
                            .toList(growable: false),
                        image.toMessageImage(),
                      )
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
          cacheWidth: _imageCacheExtent(76),
          cacheHeight: _imageCacheExtent(76),
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
        !_preparingSend &&
        (_msgCtrl.text.trim().isNotEmpty || _pendingImages.isNotEmpty);
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
      return InkWell(
        onTap: _stopVoice,
        borderRadius: BorderRadius.circular(20),
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
                '点击转文字',
                style: TextStyle(fontSize: 12, color: Colors.white),
              ),
            ],
          ),
        ),
      );
    }
    if (_preparingSend) {
      return const Padding(
        padding: EdgeInsets.all(8),
        child: SizedBox(
          width: 18,
          height: 18,
          child: CircularProgressIndicator(strokeWidth: 2),
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
    return Tooltip(
      message: hasSpeech ? '长按语音输入' : '长按使用系统语音',
      child: GestureDetector(
        onTap: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('长按按钮开始录音，松开自动转文字'),
              duration: Duration(seconds: 1),
            ),
          );
        },
        onLongPressStart: (_) => _voice(),
        onLongPressEnd: (_) => _stopVoice(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(
            hasSpeech ? Icons.mic_none : Icons.mic_none_outlined,
            size: 22,
            color: Theme.of(context).colorScheme.outline,
          ),
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

  Widget _recOverlay() => Container(
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
          _speech.isListening ? '正在聆听...' : '正在录音，点击右侧按钮转文字',
          style: TextStyle(color: Colors.red[400], fontSize: 14),
        ),
      ],
    ),
  );
}

@visibleForTesting
Future<Object?> retryUserContent(
  Message message,
  Future<Object?> Function() prepareAttachments,
) {
  if (message.images.isEmpty) {
    return Future.value(message.modelContextContent ?? message.content);
  }
  return prepareAttachments();
}

class _PreparedUserContent {
  const _PreparedUserContent({
    required this.apiContent,
    required this.textContext,
  });

  final Object apiContent;
  final String textContext;
}

ModelConfig? _findModelConfigById(List<ModelConfig> models, String id) {
  try {
    return models.firstWhere((m) => m.id == id);
  } catch (_) {
    return null;
  }
}
