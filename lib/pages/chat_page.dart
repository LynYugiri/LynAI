import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import '../models/model_config.dart';
import '../providers/conversation_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/api_service.dart';
import '../widgets/latex_renderer.dart';

class ChatPage extends StatefulWidget {
  final String? conversationId;
  final VoidCallback? onConversationLoaded;
  final VoidCallback? onNavigateToSettings;

  const ChatPage({
    super.key,
    this.conversationId,
    this.onConversationLoaded,
    this.onNavigateToSettings,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  final _screenshotController = ScreenshotController();
  final _apiService = ApiService();

  String? _currentConversationId;
  bool _isThinking = true;
  bool _isStreaming = false;
  bool _showAttachmentMenu = false;
  bool _showModelMenu = false;
  bool _isRecording = false;
  String? _thinkingContentForCurrent;
  bool _thinkingExpanded = false;
  Map<String, String?> _thinkingContents = {};

  late stt.SpeechToText _speech;
  StreamSubscription<StreamChunk>? _streamSubscription;

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    if (widget.conversationId != null) {
      _currentConversationId = widget.conversationId;
      widget.onConversationLoaded?.call();
    }
  }

  @override
  void didUpdateWidget(ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.conversationId != null &&
        widget.conversationId != _currentConversationId) {
      setState(() {
        _currentConversationId = widget.conversationId;
        _thinkingContentForCurrent =
            _thinkingContents[_currentConversationId];
        _thinkingExpanded = false;
      });
      widget.onConversationLoaded?.call();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    _streamSubscription?.cancel();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  ModelConfig? _getCurrentModel(ModelConfigProvider modelProvider) {
    if (modelProvider.models.isEmpty) return null;
    if (_currentConversationId != null) {
      final provider = context.read<ConversationProvider>();
      final conversation =
          provider.getConversation(_currentConversationId!);
      if (conversation != null) {
        try {
          return modelProvider.models
              .firstWhere((m) => m.id == conversation.modelId);
        } catch (_) {}
      }
    }
    return modelProvider.models.first;
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isStreaming) return;

    final provider = context.read<ConversationProvider>();
    final modelProvider = context.read<ModelConfigProvider>();

    if (modelProvider.models.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中添加 AI 模型')),
        );
      }
      return;
    }

    final currentModel = _getCurrentModel(modelProvider);
    if (currentModel == null) return;

    if (_currentConversationId == null) {
      _currentConversationId = provider.createConversation(currentModel.id);
    }

    provider.addMessage(_currentConversationId!, 'user', text);
    _messageController.clear();
    _scrollToBottom();

    provider.addMessage(_currentConversationId!, 'assistant', '');

    setState(() {
      _isStreaming = true;
      _thinkingContentForCurrent = null;
    });

    final conversation = provider.getConversation(_currentConversationId!);
    if (conversation == null) return;

    final messages = conversation.messages
        .where((m) => m.role != 'assistant' || m.content.isNotEmpty)
        .map((m) => {'role': m.role, 'content': m.content})
        .toList();

    if (messages.isNotEmpty && messages.last['role'] == 'assistant') {
      messages.removeLast();
    }

    _doSendToModel(currentModel, messages);
  }

  void _doSendToModel(ModelConfig model, List<Map<String, String>> messages) {
    final provider = context.read<ConversationProvider>();
    final convId = _currentConversationId!;

    final stream = _apiService.sendStreamRequest(
      model,
      messages,
      thinking: _isThinking,
    );

    String fullContent = '';
    String fullThinking = '';
    _streamSubscription?.cancel();
    _streamSubscription = stream.listen(
      (chunk) {
        if (!mounted) return;
        if (chunk.content != null) {
          fullContent += chunk.content!;
        }
        if (chunk.reasoningContent != null) {
          fullThinking += chunk.reasoningContent!;
        }
        if (chunk.isDone) {
          setState(() {
            _isStreaming = false;
            if (fullThinking.isNotEmpty) {
              _thinkingContentForCurrent = fullThinking;
              _thinkingContents[convId] = fullThinking;
            }
          });
          provider.updateLastMessage(convId, fullContent);
        } else {
          provider.updateLastMessage(convId, fullContent);
          if (fullThinking.isNotEmpty) {
            setState(() {
              _thinkingContentForCurrent = fullThinking;
            });
          }
        }
        _scrollToBottom();
      },
      onError: (error) {
        if (!mounted) return;
        setState(() => _isStreaming = false);
        provider.updateLastMessage(convId, '请求失败: $error');
      },
      onDone: () {
        if (!mounted) return;
        setState(() => _isStreaming = false);
      },
    );
  }

  void _switchModel(ModelConfig model) {
    final provider = context.read<ConversationProvider>();
    if (_currentConversationId != null) {
      provider.updateConversationTitle(_currentConversationId!, model.name);
    }
    setState(() {});
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已切换到: ${model.name}'),
          duration: const Duration(seconds: 1),
        ),
      );
    }
  }

  void _retryLastMessage() {
    if (_currentConversationId == null || _isStreaming) return;
    final provider = context.read<ConversationProvider>();
    final conversation =
        provider.getConversation(_currentConversationId!);
    if (conversation == null) return;

    if (conversation.messages.isNotEmpty &&
        conversation.messages.last.role == 'assistant') {
      provider.deleteMessage(
          _currentConversationId!, conversation.messages.last.id);
    }
    final userMessages =
        conversation.messages.where((m) => m.role == 'user').toList();
    if (userMessages.isNotEmpty) {
      _messageController.text = userMessages.last.content;
      _sendMessage();
    }
  }

  void _copyMessage(String content) {
    Clipboard.setData(ClipboardData(text: content));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已复制到剪贴板'),
          duration: Duration(seconds: 1),
        ),
      );
    }
  }

  Future<void> _shareAsImage() async {
    try {
      final imageBytes = await _screenshotController.capture(
        pixelRatio: 2.0,
        delay: const Duration(milliseconds: 100),
      );
      if (imageBytes == null) return;

      final dir = Directory.systemTemp;
      final file = File(
          '${dir.path}/lynai_share_${DateTime.now().millisecondsSinceEpoch}.png');
      await file.writeAsBytes(imageBytes);

      if (mounted) {
        await SharePlus.instance.share(
          ShareParams(
            files: [XFile(file.path)],
            text: 'LynAI 对话分享',
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('分享失败: $e')),
        );
      }
    }
  }

  Future<void> _pickImageOrFile() async {
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final provider = context.read<ConversationProvider>();
    final modelProvider = context.read<ModelConfigProvider>();

    if (modelProvider.models.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('请先在设置中添加 AI 模型')),
        );
      }
      return;
    }

    final currentModel = _getCurrentModel(modelProvider);
    if (currentModel == null) return;

    final settings = context.read<SettingsProvider>().settings;
    final imageModelId = settings.imageModelId;
    final imagePrompt = settings.imagePrompt;

    if (_currentConversationId == null) {
      _currentConversationId = provider.createConversation(currentModel.id);
    }

    final file = File(picked.path);
    final sizeBytes = await file.length();
    provider.addMessage(_currentConversationId!, 'user',
        '[图片: ${picked.name} (${_formatFileSize(sizeBytes)})]');
    _scrollToBottom();

    // 如果设置了图片转述模型，先发送到该模型进行转述
    if (imageModelId != null && imageModelId.isNotEmpty) {
      try {
        final imageModel = modelProvider.models
            .firstWhere((m) => m.id == imageModelId);
        provider.addMessage(_currentConversationId!, 'assistant', '');
        setState(() => _isStreaming = true);

        final messages = [
          {'role': 'user', 'content': imagePrompt},
        ];

        final response = await _apiService.sendChatRequest(
          imageModel,
          messages,
          thinking: false,
        );

        provider.updateLastMessage(
            _currentConversationId!, '[图片转述] ${response.content}');
        setState(() => _isStreaming = false);

        // 将转述结果发送给当前聊天模型
        provider.addMessage(_currentConversationId!, 'assistant', '');
        final convMessages = [
          ...provider
              .getConversation(_currentConversationId!)!
              .messages
              .where((m) =>
                  m.role != 'assistant' || m.content.isNotEmpty)
              .map((m) => {'role': m.role, 'content': m.content}),
        ];
        if (convMessages.isNotEmpty &&
            convMessages.last['role'] == 'assistant') {
          convMessages.removeLast();
        }

        _doSendToModel(currentModel, convMessages);
      } catch (e) {
        if (mounted) {
          setState(() => _isStreaming = false);
          provider.updateLastMessage(
              _currentConversationId!, '图片转述失败: $e');
        }
      }
    }
  }

  Future<void> _handleVoiceAction() async {
    final settings = context.read<SettingsProvider>().settings;
    final modelProvider = context.read<ModelConfigProvider>();

    // 如果未设置语音模型，直接当作发送按钮
    if (settings.speechModelId == null ||
        settings.speechModelId!.isEmpty) {
      _sendMessage();
      return;
    }

    // 已设置语音模型 → 开始录音
    final available = await _speech.initialize(
      onStatus: (status) {
        if (status == 'done' || status == 'notListening') {
          setState(() => _isRecording = false);
        }
      },
      onError: (error) {
        setState(() => _isRecording = false);
      },
    );

    if (available) {
      setState(() => _isRecording = true);
      _speech.listen(
        onResult: (result) {
          _messageController.text = result.recognizedWords;
          if (result.finalResult) {
            setState(() => _isRecording = false);
            _processSpeechResult(result.recognizedWords,
                settings.speechModelId!, modelProvider);
          }
        },
        localeId: 'zh_CN',
      );
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('语音识别不可用')),
        );
      }
    }
  }

  Future<void> _processSpeechResult(
      String speech,
      String speechModelId,
      ModelConfigProvider modelProvider) async {
    if (speech.trim().isEmpty) return;

    final provider = context.read<ConversationProvider>();
    final currentModel = _getCurrentModel(modelProvider);
    if (currentModel == null) return;

    if (_currentConversationId == null) {
      _currentConversationId = provider.createConversation(currentModel.id);
    }

    provider.addMessage(_currentConversationId!, 'user', speech);
    _messageController.clear();
    _scrollToBottom();

    provider.addMessage(_currentConversationId!, 'assistant', '');
    setState(() => _isStreaming = true);

    try {
      final speechModel = modelProvider.models
          .firstWhere((m) => m.id == speechModelId);
      final response = await _apiService.sendChatRequest(
        speechModel,
        [
          {
            'role': 'user',
            'content': '请将以下语音识别结果进行整理和修正，直接输出修正后的文字，不要添加任何解释:\n$speech'
          },
        ],
        thinking: false,
      );

      final transcribed = response.content.trim();
      provider.updateLastMessage(_currentConversationId!, transcribed);

      // 用修正后的文字发送给当前对话模型
      provider.addMessage(_currentConversationId!, 'assistant', '');
      final convMessages = provider
          .getConversation(_currentConversationId!)!
          .messages
          .where(
              (m) => m.role != 'assistant' || m.content.isNotEmpty)
          .map((m) => {'role': m.role, 'content': m.content})
          .toList();
      if (convMessages.isNotEmpty &&
          convMessages.last['role'] == 'assistant') {
        convMessages.removeLast();
      }

      _doSendToModel(currentModel, convMessages);
    } catch (e) {
      if (mounted) {
        setState(() => _isStreaming = false);
        provider.updateLastMessage(
            _currentConversationId!, '语音处理失败: $e');
      }
    }
  }

  void _stopVoiceInput() {
    _speech.stop();
    setState(() => _isRecording = false);
  }

  void _selectHistoryConversation(String conversationId) {
    setState(() {
      _currentConversationId = conversationId;
      _thinkingContentForCurrent =
          _thinkingContents[conversationId];
      _thinkingExpanded = false;
    });
    Navigator.pop(context);
  }

  String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    final conversationProvider = context.watch<ConversationProvider>();
    final modelProvider = context.watch<ModelConfigProvider>();
    final currentModel = _getCurrentModel(modelProvider);
    final conversation =
        conversationProvider.getConversation(_currentConversationId ?? '');

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.history),
            tooltip: '历史记录',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(conversation?.title ?? '新对话'),
        centerTitle: true,
        actions: [
          if (_currentConversationId != null)
            IconButton(
              icon: const Icon(Icons.add_comment_outlined),
              tooltip: '新建对话',
              onPressed: () {
                setState(() {
                  _currentConversationId = null;
                  _thinkingContentForCurrent = null;
                });
              },
            ),
        ],
      ),
      drawer: _buildHistoryDrawer(context),
      body: Screenshot(
        controller: _screenshotController,
        child: _buildChatBody(
            conversation, currentModel, modelProvider),
      ),
    );
  }

  Widget _buildHistoryDrawer(BuildContext context) {
    return Drawer(
      child: _HistoryDrawerContent(
        onSelectConversation: _selectHistoryConversation,
        currentConversationId: _currentConversationId,
      ),
    );
  }

  Widget _buildChatBody(
    dynamic conversation,
    ModelConfig? currentModel,
    ModelConfigProvider modelProvider,
  ) {
    final messages = conversation?.messages ?? <dynamic>[];

    return Column(
      children: [
        Expanded(
          child: messages.isEmpty
              ? _buildEmptyState()
              : ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final message = messages[index];
                    final isLastAi = message.role == 'assistant' &&
                        index == messages.length - 1;
                    return _buildMessageBubble(
                        message, isLastAi);
                  },
                ),
        ),
        _buildInputArea(currentModel, modelProvider),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.chat_bubble_outline,
              size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text('开始新对话',
              style: TextStyle(
                  fontSize: 20,
                  color: Colors.grey[500],
                  fontWeight: FontWeight.w300)),
          const SizedBox(height: 8),
          Text('在下方输入你的问题',
              style:
                  TextStyle(fontSize: 14, color: Colors.grey[400])),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(dynamic message, bool isLastAi) {
    final isUser = message.role == 'user';

    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          constraints: BoxConstraints(
            maxWidth: MediaQuery.of(context).size.width * 0.75,
          ),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
            borderRadius: const BorderRadius.only(
              topLeft: Radius.circular(16),
              topRight: Radius.circular(16),
              bottomLeft: Radius.circular(16),
            ),
          ),
          child: SelectableText(message.content,
              style: const TextStyle(fontSize: 15)),
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_thinkingContentForCurrent != null &&
            _thinkingContentForCurrent!.isNotEmpty &&
            isLastAi)
          _buildThinkingSection(),
        Container(
          margin: const EdgeInsets.symmetric(vertical: 4),
          padding:
              const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
          ),
          child: message.content.isEmpty && _isStreaming
              ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : MarkdownWithLatex(content: message.content),
        ),
        if (!_isStreaming && message.content.isNotEmpty)
          _buildMessageActions(message.content),
      ],
    );
  }

  Widget _buildThinkingSection() {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 2, horizontal: 4),
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(
            color: Theme.of(context)
                .colorScheme
                .secondary
                .withValues(alpha: 0.3),
            width: 2,
          ),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(
                () => _thinkingExpanded = !_thinkingExpanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    _thinkingExpanded
                        ? Icons.expand_less
                        : Icons.expand_more,
                    size: 14,
                    color: Colors.grey[500],
                  ),
                  const SizedBox(width: 4),
                  Text('思考过程',
                      style: TextStyle(
                          fontSize: 11,
                          color: Colors.grey[500])),
                ],
              ),
            ),
          ),
          if (_thinkingExpanded)
            Padding(
              padding: const EdgeInsets.symmetric(
                  horizontal: 8, vertical: 4),
              child: Text(
                _thinkingContentForCurrent!,
                style: TextStyle(
                  fontSize: 11,
                  color: Colors.grey[400],
                  fontStyle: FontStyle.italic,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageActions(String content) {
    return Padding(
      padding: const EdgeInsets.only(left: 8, top: 2),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildActionButton(
            icon: Icons.copy,
            tooltip: '复制',
            onTap: () => _copyMessage(content),
          ),
          const SizedBox(width: 4),
          _buildActionButton(
            icon: Icons.share,
            tooltip: '分享',
            onTap: _shareAsImage,
          ),
          const SizedBox(width: 4),
          _buildActionButton(
            icon: Icons.refresh,
            tooltip: '重试',
            onTap: _retryLastMessage,
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Icon(icon, size: 16, color: Colors.grey[400]),
      ),
    );
  }

  Widget _buildInputArea(
      ModelConfig? currentModel, ModelConfigProvider modelProvider) {
    final settings = context.read<SettingsProvider>().settings;
    final hasSpeechModel = settings.speechModelId != null &&
        settings.speechModelId!.isNotEmpty;

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
          // Model selector + text input
          if (_showModelMenu) _buildModelList(modelProvider),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              _buildModelSelector(currentModel, modelProvider),
              const SizedBox(width: 4),
              Expanded(
                child: _isRecording
                    ? _buildRecordingOverlay()
                    : TextField(
                        controller: _messageController,
                        focusNode: _focusNode,
                        style: const TextStyle(
                            fontSize: 16, fontFamily: 'monospace'),
                        decoration: const InputDecoration(
                          hintText: '输入消息...',
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 8, vertical: 10),
                        ),
                        maxLines: 5,
                        minLines: 1,
                        textInputAction: TextInputAction.send,
                        onSubmitted: (_) => _sendMessage(),
                        onChanged: (_) => setState(() {}),
                      ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              _buildSettingsButton(),
              const SizedBox(width: 4),
              _buildThinkToggle(),
              const Spacer(),
              _buildAttachmentButton(),
              const SizedBox(width: 4),
              _buildVoiceOrSendButton(hasSpeechModel),
            ],
          ),
          if (_showAttachmentMenu) _buildAttachmentMenu(),
        ],
      ),
    );
  }

  Widget _buildModelList(ModelConfigProvider modelProvider) {
    final currentModel = _getCurrentModel(modelProvider);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      constraints: const BoxConstraints(maxHeight: 200),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(10),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: modelProvider.models.length,
        itemBuilder: (context, index) {
          final model = modelProvider.models[index];
          final isSelected =
              currentModel != null && model.id == currentModel.id;
          return ListTile(
            dense: true,
            leading: Icon(
              isSelected ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: isSelected
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey,
            ),
            title: Text(model.name,
                style: const TextStyle(fontSize: 14)),
            subtitle: Text(model.modelName,
                style: const TextStyle(fontSize: 11)),
            onTap: () {
              _switchModel(model);
              setState(() => _showModelMenu = false);
            },
          );
        },
      ),
    );
  }

  Widget _buildModelSelector(
      ModelConfig? currentModel, ModelConfigProvider modelProvider) {
    if (currentModel == null) {
      return Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Icon(Icons.smart_toy, size: 18, color: Colors.grey[400]),
      );
    }

    if (_showModelMenu) {
      return InkWell(
        onTap: () => setState(() => _showModelMenu = false),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.1),
            border: Border.all(
              color: Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.3),
            ),
          ),
          child: Icon(Icons.arrow_drop_up,
              size: 22, color: Theme.of(context).colorScheme.primary),
        ),
      );
    }

    return InkWell(
      onTap: () => setState(() => _showModelMenu = true),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: Theme.of(context)
                .colorScheme
                .primary
                .withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.smart_toy,
                size: 18,
                color: Theme.of(context).colorScheme.primary),
            const SizedBox(width: 2),
            Text(currentModel.name,
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                    color: Theme.of(context).colorScheme.primary)),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18),
          ],
        ),
      ),
    );
  }

  Widget _buildSettingsButton() {
    return InkWell(
      onTap: () {
        widget.onNavigateToSettings?.call();
      },
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
              color: Colors.grey.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.settings, size: 14, color: Colors.grey[500]),
            const SizedBox(width: 3),
            Text('设置',
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildThinkToggle() {
    return InkWell(
      onTap: () => setState(() => _isThinking = !_isThinking),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: _isThinking
                ? Theme.of(context).colorScheme.primary
                : Colors.grey.withValues(alpha: 0.3),
          ),
          color: _isThinking
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.1)
              : null,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.psychology,
              size: 16,
              color: _isThinking
                  ? Theme.of(context).colorScheme.primary
                  : Colors.grey[400],
            ),
            const SizedBox(width: 3),
            Text(
              '思考',
              style: TextStyle(
                fontSize: 12,
                color: _isThinking
                    ? Theme.of(context).colorScheme.primary
                    : Colors.grey[500],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentButton() {
    return InkWell(
      onTap: () =>
          setState(() => _showAttachmentMenu = !_showAttachmentMenu),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(4),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: _showAttachmentMenu
              ? Theme.of(context)
                  .colorScheme
                  .primary
                  .withValues(alpha: 0.1)
              : null,
        ),
        child: Icon(
          Icons.add,
          size: 22,
          color: _showAttachmentMenu
              ? Theme.of(context).colorScheme.primary
              : Colors.grey[500],
        ),
      ),
    );
  }

  Widget _buildAttachmentMenu() {
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          _buildAttachmentOption(
            icon: Icons.photo_library,
            label: '图片',
            onTap: () {
              setState(() => _showAttachmentMenu = false);
              _pickImageOrFile();
            },
          ),
          const SizedBox(width: 12),
          _buildAttachmentOption(
            icon: Icons.attach_file,
            label: '文件',
            onTap: () {
              setState(() => _showAttachmentMenu = false);
              _pickImageOrFile();
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAttachmentOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 4),
            Text(label,
                style: TextStyle(
                    fontSize: 12, color: Colors.grey[600])),
          ],
        ),
      ),
    );
  }

  Widget _buildVoiceOrSendButton(bool hasSpeechModel) {
    final hasText = _messageController.text.isNotEmpty;

    if (_isRecording) {
      return GestureDetector(
        onLongPressEnd: (_) => _stopVoiceInput(),
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
              Text('松开发送',
                  style:
                      TextStyle(fontSize: 12, color: Colors.white)),
            ],
          ),
        ),
      );
    }

    if (hasText) {
      return IconButton(
        onPressed: _sendMessage,
        icon: Icon(Icons.send_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 22),
        padding: EdgeInsets.zero,
        constraints:
            const BoxConstraints(minWidth: 36, minHeight: 36),
      );
    }

    return IconButton(
      onPressed: hasSpeechModel
          ? _handleVoiceAction
          : _sendMessage,
      icon: Icon(
        hasSpeechModel ? Icons.mic_none : Icons.send_rounded,
        size: 22,
        color: hasSpeechModel
            ? Colors.grey[500]
            : Colors.grey[400],
      ),
      padding: EdgeInsets.zero,
      constraints:
          const BoxConstraints(minWidth: 36, minHeight: 36),
      tooltip: hasSpeechModel ? '语音输入' : '发送',
    );
  }

  Widget _buildRecordingOverlay() {
    return GestureDetector(
      onLongPressEnd: (_) => _stopVoiceInput(),
      child: Container(
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.1),
          borderRadius: BorderRadius.circular(12),
          border:
              Border.all(color: Colors.red.withValues(alpha: 0.3)),
        ),
        child: Row(
          children: [
            Icon(Icons.mic, size: 20, color: Colors.red[400]),
            const SizedBox(width: 8),
            Text(
              _speech.isListening ? '正在聆听...' : '长按录制语音',
              style:
                  TextStyle(color: Colors.red[400], fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}

class _HistoryDrawerContent extends StatefulWidget {
  final void Function(String conversationId) onSelectConversation;
  final String? currentConversationId;

  const _HistoryDrawerContent({
    required this.onSelectConversation,
    this.currentConversationId,
  });

  @override
  State<_HistoryDrawerContent> createState() =>
      _HistoryDrawerContentState();
}

class _HistoryDrawerContentState extends State<_HistoryDrawerContent> {
  final _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<ConversationProvider>();
    final results = provider.searchConversations(_searchQuery);

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
                  Text('历史对话',
                      style: Theme.of(context).textTheme.titleLarge),
                ],
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _searchController,
                decoration: InputDecoration(
                  hintText: '搜索历史...',
                  prefixIcon: const Icon(Icons.search, size: 20),
                  suffixIcon: _searchQuery.isNotEmpty
                      ? IconButton(
                          icon: const Icon(Icons.clear, size: 20),
                          onPressed: () {
                            _searchController.clear();
                            setState(() => _searchQuery = '');
                          },
                        )
                      : null,
                  filled: true,
                  fillColor: Theme.of(context)
                      .colorScheme
                      .surface
                      .withValues(alpha: 0.5),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(8),
                    borderSide: BorderSide.none,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 8),
                ),
                onChanged: (value) =>
                    setState(() => _searchQuery = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    _searchQuery.isEmpty ? '暂无历史对话' : '无匹配结果',
                    style: TextStyle(color: Colors.grey[500]),
                  ),
                )
              : ListView.builder(
                  itemCount: results.length,
                  itemBuilder: (context, index) {
                    final conv = results[index]['conversation'];
                    final isActive =
                        conv.id == widget.currentConversationId;
                    return ListTile(
                      selected: isActive,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3),
                      leading: const Icon(Icons.chat, size: 20),
                      title: Text(conv.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontWeight: isActive
                                  ? FontWeight.bold
                                  : FontWeight.normal)),
                      subtitle: Text(conv.preview,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 12)),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            size: 18),
                        onPressed: () {
                          context
                              .read<ConversationProvider>()
                              .deleteConversation(conv.id);
                          if (conv.id ==
                              widget.currentConversationId) {
                            widget.onSelectConversation('');
                          }
                        },
                      ),
                      onLongPress: () {
                        context
                            .read<ConversationProvider>()
                            .deleteConversation(conv.id);
                        if (conv.id ==
                            widget.currentConversationId) {
                          widget.onSelectConversation('');
                        }
                      },
                      onTap: () =>
                          widget.onSelectConversation(conv.id),
                    );
                  },
                ),
        ),
      ],
    );
  }
}
