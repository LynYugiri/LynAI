import 'dart:async';
import 'dart:io';
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
import '../models/message.dart';
import '../models/model_config.dart';
import '../models/app_settings.dart';
import '../models/system_prompt.dart';
import '../providers/conversation_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../widgets/latex_renderer.dart';

class _RetryEntry {
  String userContent;
  String? assistantId;
  String? assistantContent;
  String? thinkingContent;
  _RetryEntry(this.userContent);
}

class _PendingImage {
  final String path;
  final String name;
  final int size;
  const _PendingImage({
    required this.path,
    required this.name,
    required this.size,
  });

  MessageImage toMessageImage() =>
      MessageImage(path: path, name: name, size: size);
}

/// 文件名安全化，避免用户相册文件名中包含路径分隔符或特殊字符。
String _safeFileName(String name) {
  final safe = name.replaceAll(RegExp(r'[^A-Za-z0-9._-]+'), '_');
  return safe.isEmpty ? 'image' : safe;
}

class ChatPage extends StatefulWidget {
  final String? conversationId;
  final VoidCallback? onConversationLoaded;
  const ChatPage({super.key, this.conversationId, this.onConversationLoaded});

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
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
  bool _scrollingToBottom = false;
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

  int _streamGen = 0;

  final List<_RetryEntry> _retryHistory = [];
  String? _retryMsgId;
  int _retryIdx = 0;

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
    }
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
    _sub?.cancel();
    _audioRecorder.dispose();
    _msgCtrl.dispose();
    _scrollCtrl.dispose();
    _focusNode.dispose();
    super.dispose();
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
    if (_scrollingToBottom) return false;
    if (notification is ScrollUpdateNotification ||
        notification is ScrollEndNotification) {
      _syncBottomState();
    }
    return false;
  }

  void _scrollEnd({bool force = false}) {
    if (!force && !_autoScrollToBottom) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        if (!force && !_autoScrollToBottom) return;
        _scrollingToBottom = true;
        final scrollGen = ++_scrollGen;
        _scrollCtrl
            .animateTo(
              _scrollCtrl.position.maxScrollExtent,
              duration: const Duration(milliseconds: 300),
              curve: Curves.easeOut,
            )
            .whenComplete(() {
              if (!mounted || scrollGen != _scrollGen) return;
              _scrollingToBottom = false;
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
    final set = context.read<SettingsProvider>().settings;
    return ConversationSettings(
      modelId: model.id,
      thinking: _thinking,
      selectedSystemPromptId: set.selectedSystemPromptId,
      systemPrompt: set.systemPrompt,
      speechModelId: set.speechModelId,
      imageModelId: set.imageModelId,
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

  Future<void> _send() async {
    final text = _msgCtrl.text.trim();
    if ((text.isEmpty && _pendingImages.isEmpty) || _streaming) return;
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    if (mp.modelsByCategory(ModelConfig.categoryChat).isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('请先在设置中添加 AI 模型')));
      }
      return;
    }
    final model = _getModel(mp);
    if (model == null) return;
    _convId ??= cp.createConversation(_currentConversationSettings(model));
    _pendingModelId = null;
    _clearRetryState();
    final images = _pendingImages.map((e) => e.toMessageImage()).toList();
    cp.addMessage(_convId!, 'user', text, images: images);
    _msgCtrl.clear();
    setState(() {
      _pendingImages.clear();
      _streaming = true;
      _thinkingTxt = null;
    });
    _scrollEnd(force: true);
    cp.addMessage(_convId!, 'assistant', '');
    try {
      final apiUserContent = await _buildUserContentWithImages(text, images);
      if (!mounted) return;
      _doSend(model, lastUserContentOverride: apiUserContent);
    } catch (e) {
      if (!mounted) return;
      setState(() => _streaming = false);
      cp.updateLastMessage(_convId!, '图片处理失败: $e', save: true);
    }
  }

  void _doSend(ModelConfig model, {String? lastUserContentOverride}) {
    final cid = _convId;
    if (cid == null) return;
    final conv = context.read<ConversationProvider>().getConversation(cid);
    if (conv == null) return;
    final msgs = _buildApiMessages(
      conv,
      lastUserContentOverride: lastUserContentOverride,
    );
    _doStream(model, msgs);
  }

  void _sendRetry(String text) {
    if (_streaming || _convId == null) return;
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    final model = _getModel(mp);
    if (model == null) return;
    final conv = cp.getConversation(_convId!);
    if (conv == null) return;
    final lastUser = conv.messages.where((m) => m.role == 'user').last;
    _retryMsgId = lastUser.id;

    final lastAssistant = conv.messages
        .where((m) => m.role == 'assistant')
        .toList();
    if (lastAssistant.isNotEmpty && lastAssistant.last.content.isNotEmpty) {
      _saveRetryHistoryEntry(
        lastUser.content,
        lastAssistant.last.id,
        lastAssistant.last.content,
      );
    }

    _retryHistory.add(_RetryEntry(text));
    _retryIdx = _retryHistory.length - 1;
    cp.updateMessageContent(_convId!, lastUser.id, text);
    if (lastAssistant.isNotEmpty) {
      _thinkMap.remove(lastAssistant.last.id);
      cp.deleteMessage(_convId!, lastAssistant.last.id);
    }
    _scrollEnd(force: true);
    cp.addMessage(_convId!, 'assistant', '');
    setState(() {
      _streaming = true;
      _thinkingTxt = null;
    });
    _doSend(model);
  }

  List<Map<String, dynamic>> _buildApiMessages(
    Conversation conv, {
    String? lastUserContentOverride,
  }) {
    final msgs = <Map<String, dynamic>>[];
    final promptContent = conv.settings.selectedSystemPromptId != null
        ? context.read<SettingsProvider>().effectiveSystemPromptFor(
            conv.settings.selectedSystemPromptId,
            conv.settings.systemPrompt,
          )
        : conv.settings.systemPrompt;
    if (promptContent.isNotEmpty) {
      msgs.add({'role': 'system', 'content': promptContent});
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
      });
    }
    return msgs;
  }

  void _doStream(ModelConfig model, List<Map<String, dynamic>> msgs) {
    if (!mounted) return;
    final cp = context.read<ConversationProvider>();
    final cid = _convId!;
    final gen = ++_streamGen;
    final stream = _api.sendStreamRequest(model, msgs, thinking: _thinking);
    String buf = '', thinkBuf = '';
    _sub?.cancel();
    _sub = stream.listen(
      (chunk) {
        if (!mounted || gen != _streamGen) return;
        if (chunk.content != null) buf += chunk.content!;
        if (chunk.reasoningContent != null) thinkBuf += chunk.reasoningContent!;
        if (chunk.isDone) {
          final think = thinkBuf.isNotEmpty ? thinkBuf : null;
          setState(() {
            _streaming = false;
            _thinkingTxt = think;
          });
          cp.updateLastMessage(cid, buf, save: true);
          final conv = cp.getConversation(cid);
          if (conv != null && conv.messages.isNotEmpty) {
            final lastMsg = conv.messages.last;
            if (think != null) _thinkMap[lastMsg.id] = think;
          }
          if (_retryHistory.isNotEmpty && _retryIdx < _retryHistory.length) {
            if (conv != null && conv.messages.isNotEmpty) {
              final lastMsg = conv.messages.last;
              _retryHistory[_retryIdx].assistantId = lastMsg.id;
              _retryHistory[_retryIdx].assistantContent = buf;
              _retryHistory[_retryIdx].thinkingContent = think;
            }
          }
        } else {
          cp.updateLastMessage(cid, buf, save: false);
          if (thinkBuf.isNotEmpty) setState(() => _thinkingTxt = thinkBuf);
        }
        _scrollEnd();
      },
      onError: (e) {
        if (!mounted || gen != _streamGen) return;
        setState(() => _streaming = false);
        String msg = e.toString();
        if (msg.startsWith('Exception: ')) msg = msg.substring(11);
        final display = buf.isNotEmpty
            ? '$buf\n\n---\n请求失败: $msg'
            : '请求失败: $msg';
        cp.updateLastMessage(cid, display, save: true);
      },
      onDone: () {
        if (!mounted || gen != _streamGen) return;
        if (_streaming) {
          final think = thinkBuf.isNotEmpty ? thinkBuf : null;
          setState(() {
            _streaming = false;
            _thinkingTxt = think;
          });
          cp.updateLastMessage(cid, buf, save: true);
          final conv = cp.getConversation(cid);
          if (conv != null && conv.messages.isNotEmpty) {
            final lastMsg = conv.messages.last;
            if (think != null) _thinkMap[lastMsg.id] = think;
          }
          if (_retryHistory.isNotEmpty && _retryIdx < _retryHistory.length) {
            if (conv != null && conv.messages.isNotEmpty) {
              final lastMsg = conv.messages.last;
              _retryHistory[_retryIdx].assistantId = lastMsg.id;
              _retryHistory[_retryIdx].assistantContent = buf;
              _retryHistory[_retryIdx].thinkingContent = think;
            }
          }
        } else {
          setState(() => _streaming = false);
        }
      },
    );
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

  void _retry() {
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
    _retryMsgId = lastUser.id;

    final lastAssistant = assistantMessages.last;
    if (lastAssistant.content.isNotEmpty) {
      _saveRetryHistoryEntry(
        lastUser.content,
        lastAssistant.id,
        lastAssistant.content,
      );
    }

    _retryHistory.add(_RetryEntry(lastUser.content));
    _retryIdx = _retryHistory.length - 1;
    _thinkMap.remove(lastAssistant.id);
    cp.deleteMessage(_convId!, lastAssistant.id);
    cp.addMessage(_convId!, 'assistant', '');
    setState(() {
      _streaming = true;
      _thinkingTxt = null;
    });
    final retryModel = _getModel(context.read<ModelConfigProvider>());
    if (retryModel != null) _doSend(retryModel);
  }

  void _retryWithoutHistory() {
    if (_convId == null || _streaming) return;
    final cp = context.read<ConversationProvider>();
    final conv = cp.getConversation(_convId!);
    if (conv == null) return;
    final assistantMessages = conv.messages
        .where((m) => m.role == 'assistant')
        .toList();
    if (assistantMessages.isEmpty) return;
    final lastAssistant = assistantMessages.last;
    _thinkMap.remove(lastAssistant.id);
    cp.deleteMessage(_convId!, lastAssistant.id);
    cp.addMessage(_convId!, 'assistant', '');
    setState(() {
      _streaming = true;
      _thinkingTxt = null;
    });
    final retryModel = _getModel(context.read<ModelConfigProvider>());
    if (retryModel != null) _doSend(retryModel);
  }

  void _saveRetryHistoryEntry(
    String userContent,
    String assistantId,
    String assistantContent,
  ) {
    if (_retryHistory.isEmpty) {
      final oldEntry = _RetryEntry(userContent);
      oldEntry.assistantId = assistantId;
      oldEntry.assistantContent = assistantContent;
      oldEntry.thinkingContent = _thinkingTxt ?? _thinkMap[assistantId];
      _retryHistory.add(oldEntry);
    } else if (_retryIdx < _retryHistory.length) {
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

  void _startShareSelection() {
    final conv = _convId == null
        ? null
        : context.read<ConversationProvider>().getConversation(_convId!);
    if (conv == null || conv.messages.isEmpty) return;
    setState(() {
      _shareSelecting = true;
      _selectedShareMessageIds.clear();
    });
  }

  void _cancelShareSelection() {
    setState(() {
      _shareSelecting = false;
      _selectedShareMessageIds.clear();
    });
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
      final bytes = await _captureShareImage();
      if (bytes == null) return;
      final f = File(
        '${Directory.systemTemp.path}/lynai_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await f.writeAsBytes(bytes);
      if (mounted) {
        if (_isDesktopPlatform) {
          final clipboard = SystemClipboard.instance;
          if (clipboard == null) {
            throw Exception('当前平台不支持写入剪贴板');
          }
          final item = DataWriterItem(suggestedName: 'LynAI 对话.png');
          item.add(Formats.png(bytes));
          await clipboard.write([item]);
          if (mounted) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(const SnackBar(content: Text('长图已复制到剪贴板')));
          }
        } else {
          await SharePlus.instance.share(
            ShareParams(files: [XFile(f.path)], text: 'LynAI 对话'),
          );
        }
        _cancelShareSelection();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('分享失败: $e')));
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
      final bytes = await _captureShareImage();
      if (bytes == null) return;
      final dir = _isDesktopPlatform
          ? await getDownloadsDirectory()
          : await getApplicationDocumentsDirectory();
      if (dir == null) throw Exception('无法获取保存目录');
      final file = File(
        '${dir.path}/lynai_share_${DateTime.now().millisecondsSinceEpoch}.png',
      );
      await file.writeAsBytes(bytes, flush: true);
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('长图已保存到 ${file.path}')));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('保存失败: $e')));
    } finally {
      if (mounted) setState(() => _sharingImage = false);
    }
  }

  Future<Uint8List?> _captureShareImage() async {
    if (_convId == null) return null;
    final conv = context.read<ConversationProvider>().getConversation(_convId!);
    if (conv == null) return null;
    final selected = conv.messages
        .where((m) => _selectedShareMessageIds.contains(m.id))
        .toList(growable: false);
    if (selected.isEmpty) return null;
    final settings = context.read<SettingsProvider>().settings;
    final brightness = Theme.of(context).brightness;
    final shareWidget = _ShareConversationImage(
      title: conv.title,
      messages: selected,
      seedColor: settings.themeColor,
      brightness: brightness,
    );
    final pixelRatio = selected.length > 20 ? 1.25 : 1.75;
    try {
      return await _screenshotCtrl.captureFromLongWidget(
        shareWidget,
        pixelRatio: pixelRatio,
        context: context,
        constraints: const BoxConstraints(maxWidth: 720),
      );
    } catch (_) {
      return _screenshotCtrl.captureFromWidget(
        shareWidget,
        pixelRatio: 1.0,
        context: context,
      );
    }
  }

  bool get _isDesktopPlatform {
    return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
  }

  Future<void> _pickImg() async {
    if (_streaming) return;
    XFile? picked;
    try {
      picked = await ImagePicker().pickImage(source: ImageSource.gallery);
      if (picked == null) return;
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('无法读取图片，请检查相册权限: $e')));
      return;
    }
    if (!mounted) return;
    late final File storedFile;
    late final int sz;
    try {
      final source = File(picked.path);
      final dir = await getApplicationDocumentsDirectory();
      final imageDir = Directory('${dir.path}/message_images');
      if (!await imageDir.exists()) await imageDir.create(recursive: true);
      storedFile = await source.copy(
        '${imageDir.path}/${DateTime.now().millisecondsSinceEpoch}_${_safeFileName(picked.name)}',
      );
      sz = await storedFile.length();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('图片读取失败: $e')));
      return;
    }
    setState(() {
      _pendingImages.add(
        _PendingImage(path: storedFile.path, name: picked!.name, size: sz),
      );
    });
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
          _PendingImage(path: storedFile.path, name: fileName, size: size),
        );
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('粘贴图片失败: $e')));
    }
  }

  /// 将图片附件转换成安全的文本上下文。
  ///
  /// 这里先按用户设置走 OCR 或图片识别模型，把识别结果拼回将要发送给 Chat 的
  /// 文本内容，但不会回填到输入框。
  Future<String> _buildUserContentWithImages(
    String text,
    List<MessageImage> images,
  ) async {
    final buffer = StringBuffer(text.trim());
    if (images.isEmpty) return buffer.toString();
    if (buffer.isNotEmpty) buffer.writeln('\n');
    for (final image in images) {
      buffer.writeln('[图片: ${image.name} (${_fmtSz(image.size)})]');
    }
    final set = _activeSettings() ?? _settingsToConversationSettings();
    final modelProvider = context.read<ModelConfigProvider>();
    final imageText = await _recognizeImagesForSend(images, set, modelProvider);
    if (imageText.isNotEmpty) {
      buffer.writeln(imageText);
    }
    return buffer.toString().trim();
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
      imageRecognitionModelId: settings.imageRecognitionModelId,
      imageRecognitionEnabled: settings.imageRecognitionEnabled,
      imageRecognitionPrompt: settings.imageRecognitionPrompt,
    );
  }

  Future<String> _recognizeImagesForSend(
    List<MessageImage> images,
    ConversationSettings set,
    ModelConfigProvider mp,
  ) async {
    if (images.isEmpty) return '';

    if (set.imageRecognitionEnabled) {
      final modelId = set.imageRecognitionModelId;
      if (modelId == null || modelId.isEmpty) {
        throw Exception('请先选择图片识别模型');
      }
      final model = _findModelConfigById(
        mp.modelsByCategory(ModelConfig.categoryChat),
        modelId,
      );
      if (model == null) {
        throw Exception('图片识别模型已不存在，请在设置中重新选择');
      }
      final inputs = <ChatImageInput>[];
      for (final image in images) {
        final bytes = await File(image.path).readAsBytes();
        inputs.add(
          ChatImageInput(bytes: bytes, mimeType: _mimeTypeForPath(image.path)),
        );
      }
      return _api.recognizeImageTextWithChatModel(
        model,
        set.imageRecognitionPrompt,
        inputs,
      );
    }

    final modelId = set.imageModelId;
    if (modelId == null || modelId.isEmpty) {
      return '';
    }
    final ocrModel = _findModelConfigById(mp.models, modelId);
    if (ocrModel == null) {
      return '';
    }
    final results = <String>[];
    for (final image in images) {
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

  String _mimeTypeForPath(String path) {
    final lower = path.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.webp')) return 'image/webp';
    if (lower.endsWith('.gif')) return 'image/gif';
    return 'image/jpeg';
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
        if (s == 'done' || s == 'notListening') {
          setState(() => _recording = false);
        }
      },
      onError: (_) => setState(() => _recording = false),
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
    _clearRetryState();
    _pendingModelId = null;
    _expandedThinkIds.clear();
    _thinkMap.clear();
    setState(() {
      _convId = cid.isEmpty ? null : cid;
      _thinkingTxt = null;
      _thinkExpanded = false;
    });
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
    return Scaffold(
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
              : _thinkMap[msg.id])
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (thinkForMsg != null && thinkForMsg.isNotEmpty)
          _thinkSection(thinkForMsg),
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
        if (!_streaming && !_shareSelecting) _bubbleActions(msg),
      ],
    );
  }

  Widget _messageImages(List<MessageImage> images) {
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: images.map((image) {
        final exists = File(image.path).existsSync();
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
                    child: const Text(
                      '图片文件已不存在',
                      style: TextStyle(fontSize: 12),
                    ),
                  ),
          ),
        );
      }).toList(),
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

  List<Widget> _buildPerMsgThinkSection(Message msg) {
    final think = _thinkMap[msg.id];
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

  Widget _actions(String c) => Padding(
    padding: const EdgeInsets.only(left: 8, top: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        _actBtn(Icons.copy, () => _copy(c)),
        const SizedBox(width: 4),
        _actBtn(Icons.share, _startShareSelection),
        const SizedBox(width: 4),
        _actBtn(Icons.refresh, _retry),
      ],
    ),
  );

  Widget _retryOnlyAction() => Padding(
    padding: const EdgeInsets.only(left: 8, top: 2),
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [_actBtn(Icons.refresh, _retryWithoutHistory)],
    ),
  );

  Widget _bubbleActions(Message msg) {
    if (msg.content.isEmpty ||
        msg.content.startsWith('请求失败') ||
        msg.content.startsWith('流式请求失败')) {
      return _retryOnlyAction();
    }
    return _actions(msg.content);
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
        cp.addMessage(_convId!, 'assistant', entry.assistantContent!);
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
      _streaming = false;
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
                _sendRetry(text);
              } else {
                _editStartNewConversation(msg, text);
              }
            },
            child: Text(isLastUserMsg ? '发送' : '开始新对话'),
          ),
        ],
      ),
    ).then((_) => ctrl.dispose());
  }

  void _editStartNewConversation(Message origMsg, String newText) {
    final cp = context.read<ConversationProvider>();
    final mp = context.read<ModelConfigProvider>();
    final editModel = _getModel(mp);
    if (editModel == null || _convId == null) return;
    final origConv = cp.getConversation(_convId!);
    if (origConv == null) return;
    final allMsgs = origConv.messages;
    final origMsgIdx = allMsgs.indexWhere((m) => m.id == origMsg.id);
    if (origMsgIdx == -1) return;
    _clearRetryState();
    _pendingModelId = null;
    final newConvId = cp.createConversation(
      origConv.settings.copyWith(modelId: editModel.id, thinking: _thinking),
    );
    for (int i = 0; i < origMsgIdx; i++) {
      cp.addMessage(
        newConvId,
        allMsgs[i].role,
        allMsgs[i].content,
        images: allMsgs[i].images,
      );
    }
    cp.addMessage(newConvId, 'user', newText);
    setState(() {
      _convId = newConvId;
      _streaming = true;
      _clearPendingState();
    });
    _scrollEnd();
    cp.addMessage(newConvId, 'assistant', '');
    _doSend(editModel);
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
          if (_showModelMenu) _modelList(mp),
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
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 260),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
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
                      title: Text(m.name, style: const TextStyle(fontSize: 14)),
                      subtitle: Text(
                        m.hasMultipleModels
                            ? '${m.enabledModelNames.length} 个模型'
                            : m.modelName,
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
              Icons.image_search,
              size: 18,
              color: Theme.of(context).colorScheme.primary,
            ),
            title: const Text('图片识别', style: TextStyle(fontSize: 14)),
            subtitle: const Text(
              '选择聊天模型作为图片识别模型',
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
            for (final m in models)
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
                title: Text(m.name, style: const TextStyle(fontSize: 13)),
                subtitle: Text(
                  m.hasMultipleModels
                      ? '${m.enabledModelNames.length} 个模型'
                      : m.modelName,
                  style: const TextStyle(fontSize: 11),
                ),
                onTap: () {
                  final base = _currentConversationSettings(cur ?? m);
                  _saveConversationSettings(
                    base.copyWith(imageRecognitionModelId: m.id),
                  );
                  setState(() => _showImageRecognitionList = false);
                },
              ),
        ],
      ),
    );
  }

  Widget _modelSel(ModelConfig? cur, ModelConfigProvider mp) {
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
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.3),
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
            const SizedBox(width: 4),
            Text(
              cur.modelName,
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _dialogSetBtn() => InkWell(
    onTap: _showDialogSettings,
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.tune, size: 14, color: Colors.grey[500]),
          const SizedBox(width: 3),
          Text('对话设置', style: TextStyle(fontSize: 12, color: Colors.grey[600])),
        ],
      ),
    ),
  );

  Widget _thinkBtn() => InkWell(
    onTap: () {
      final value = !_thinking;
      setState(() => _thinking = value);
      if (_convId != null) {
        final conv = context.read<ConversationProvider>().getConversation(
          _convId!,
        );
        if (conv != null) {
          _saveConversationSettings(conv.settings.copyWith(thinking: value));
        }
      } else if (_draftSettings != null) {
        _saveDraftSettings(_draftSettings!.copyWith(thinking: value));
      }
    },
    borderRadius: BorderRadius.circular(8),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: _thinking
              ? Theme.of(context).colorScheme.primary
              : Colors.grey.withValues(alpha: 0.3),
        ),
        color: _thinking
            ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
            : null,
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.psychology,
            size: 16,
            color: _thinking
                ? Theme.of(context).colorScheme.primary
                : Colors.grey[400],
          ),
          const SizedBox(width: 3),
          Text(
            '思考',
            style: TextStyle(
              fontSize: 12,
              color: _thinking
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[500],
            ),
          ),
        ],
      ),
    ),
  );

  Widget _imageRecognitionBtn() {
    final enabled =
        _activeSettings()?.imageRecognitionEnabled ??
        context.watch<SettingsProvider>().settings.imageRecognitionEnabled;
    return InkWell(
      onTap: () {
        final value = !enabled;
        final model = _getModel(context.read<ModelConfigProvider>());
        if (model == null) return;
        final settings = _currentConversationSettings(
          model,
        ).copyWith(imageRecognitionEnabled: value);
        setState(() {});
        _saveConversationSettings(settings);
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: enabled
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withValues(alpha: 0.3),
          ),
          color: enabled
              ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_search,
              size: 16,
              color: enabled
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[400],
            ),
            const SizedBox(width: 3),
            Text(
              '图片识别',
              style: TextStyle(
                fontSize: 12,
                color: enabled
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
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
        _attachOpt(Icons.photo_library, '图片', () {
          setState(() => _showAttach = false);
          _pickImg();
        }),
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
                onTap: () => _showImagePreview(image.path, image.name),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: Image.file(
                    File(image.path),
                    width: 76,
                    height: 76,
                    fit: BoxFit.cover,
                  ),
                ),
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

  Widget _voiceOrSendBtn(bool hasSpeech) {
    final hasText = _msgCtrl.text.isNotEmpty;
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
    if (hasText) {
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
    if (hasSpeech) {
      return GestureDetector(
        onLongPressStart: (_) => _voice(),
        onLongPressEnd: (_) => _stopVoice(),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Icon(Icons.mic_none, size: 22, color: Colors.grey[500]),
        ),
      );
    }
    return IconButton(
      onPressed: hasSpeech ? _voice : _send,
      icon: Icon(Icons.send_rounded, size: 22, color: Colors.grey[400]),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
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

  const _ShareConversationImage({
    required this.title,
    required this.messages,
    required this.seedColor,
    required this.brightness,
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
              'Shared from LynAI',
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
                hint: '未设置（图片将直接发送，如果非多模态模型可能会发送失败）',
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
              // 图片识别模型
              Text(
                '图片识别模型',
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
                hint: '未设置（启用图片识别按钮后将用该模型识图）',
                icon: Icons.image_search,
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
              ),
              const SizedBox(height: 16),
              // 图片识别提示词
              Text(
                '图片识别提示词',
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
  }) {
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
                    '${currentModel.name} / ${currentModel.modelName}',
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
  ) {
    final models = mp.modelsByCategory(category);
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
                title: Text(m.name, style: const TextStyle(fontSize: 14)),
                subtitle: Text(
                  m.hasMultipleModels
                      ? '${m.enabledModelNames.length} 个模型'
                      : m.modelName,
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
            hintText: '请根据下面的 OCR 识别结果回答。',
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
    final results = p.searchConversations(_q);
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
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (_, i) {
                    final c = results[i]['conversation'];
                    final active = c.id == widget.currentConvId;
                    return ListTile(
                      selected: active,
                      selectedTileColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
                      leading: const Icon(Icons.chat, size: 20),
                      title: Text(
                        c.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: active
                              ? FontWeight.bold
                              : FontWeight.normal,
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
                        onPressed: () {
                          context
                              .read<ConversationProvider>()
                              .deleteConversation(c.id);
                          if (c.id == widget.currentConvId) widget.onSelect('');
                        },
                      ),
                      onLongPress: () {
                        context.read<ConversationProvider>().deleteConversation(
                          c.id,
                        );
                        if (c.id == widget.currentConvId) widget.onSelect('');
                      },
                      onTap: () => widget.onSelect(c.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
