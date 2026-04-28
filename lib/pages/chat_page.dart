import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/conversation_provider.dart';
import '../providers/model_config_provider.dart';

/// 聊天页面
///
/// 这是应用的核心页面，提供 AI 对话功能。
///
/// 功能：
/// - 底部输入框，类似 CLI 命令行界面风格
/// - 左上角菜单按钮打开侧边栏，列出历史对话标题
/// - 侧边栏支持搜索历史对话
/// - 消息气泡展示对话内容（用户/AI 区分显示）
/// - 支持从历史对话继续聊天
class ChatPage extends StatefulWidget {
  /// 要加载的对话ID，null 表示新对话
  final String? conversationId;

  /// 对话加载完成后的回调
  final VoidCallback? onConversationLoaded;

  const ChatPage({
    super.key,
    this.conversationId,
    this.onConversationLoaded,
  });

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatPageState extends State<ChatPage> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  final _focusNode = FocusNode();
  String? _currentConversationId;

  @override
  void initState() {
    super.initState();
    // 如果有传入的对话ID，加载该对话
    if (widget.conversationId != null) {
      _currentConversationId = widget.conversationId;
      widget.onConversationLoaded?.call();
    }
  }

  @override
  void didUpdateWidget(ChatPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 当 conversationId 变化时重新加载
    if (widget.conversationId != null &&
        widget.conversationId != _currentConversationId) {
      setState(() {
        _currentConversationId = widget.conversationId;
      });
      widget.onConversationLoaded?.call();
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  /// 发送消息
  void _sendMessage() {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final provider = context.read<ConversationProvider>();
    final modelProvider = context.read<ModelConfigProvider>();

    // 如果没有当前对话，创建新对话
    if (_currentConversationId == null) {
      // 使用优先级最高的模型，如果没有则使用默认
      final modelId =
          modelProvider.models.isNotEmpty ? modelProvider.models.first.id : '';
      _currentConversationId = provider.createConversation(modelId);
    }

    // 添加用户消息
    provider.addMessage(_currentConversationId!, 'user', text);
    _messageController.clear();

    // 模拟 AI 回复（实际项目中应调用 API）
    _simulateAiResponse(provider);

    // 滚动到底部
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

  /// 模拟 AI 回复（占位实现，后续替换为真实 API 调用）
  void _simulateAiResponse(ConversationProvider provider) {
    Future.delayed(const Duration(milliseconds: 500), () {
      if (_currentConversationId == null) return;
      provider.addMessage(
        _currentConversationId!,
        'assistant',
        '这是一个模拟的 AI 回复。在实际应用中，这里会调用配置的 AI 模型 API 来获取真实回复。',
      );
    });
  }

  /// 从侧边栏选择历史对话
  void _selectHistoryConversation(String conversationId) {
    setState(() {
      _currentConversationId = conversationId;
    });
    Navigator.pop(context); // 关闭侧边栏
  }

  @override
  Widget build(BuildContext context) {
    final conversationProvider = context.watch<ConversationProvider>();
    final conversation =
        conversationProvider.getConversation(_currentConversationId ?? '');

    return Scaffold(
      appBar: AppBar(
        leading: Builder(
          builder: (ctx) => IconButton(
            icon: const Icon(Icons.menu),
            tooltip: '历史对话',
            onPressed: () => Scaffold.of(ctx).openDrawer(),
          ),
        ),
        title: Text(conversation?.title ?? '新对话'),
        centerTitle: true,
        actions: [
          if (_currentConversationId != null)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: '新建对话',
              onPressed: () {
                setState(() => _currentConversationId = null);
              },
            ),
        ],
      ),
      // 左侧抽屉：历史对话列表
      drawer: _buildHistoryDrawer(context),
      body: _buildChatBody(conversation),
    );
  }

  /// 构建历史对话抽屉（侧边栏）
  Widget _buildHistoryDrawer(BuildContext context) {
    return Drawer(
      child: _HistoryDrawerContent(
        onSelectConversation: _selectHistoryConversation,
        currentConversationId: _currentConversationId,
      ),
    );
  }

  /// 构建聊天主体
  Widget _buildChatBody(dynamic conversation) {
    final messages = conversation?.messages ?? <dynamic>[];

    return Column(
      children: [
        // 消息列表区域
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
                    return _buildMessageBubble(message);
                  },
                ),
        ),
        // 底部输入区域
        _buildInputArea(),
      ],
    );
  }

  /// 构建空状态提示
  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.chat_bubble_outline,
            size: 80,
            color: Colors.grey[300],
          ),
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
            style: TextStyle(
              fontSize: 14,
              color: Colors.grey[400],
            ),
          ),
        ],
      ),
    );
  }

  /// 构建消息气泡
  Widget _buildMessageBubble(dynamic message) {
    final isUser = message.role == 'user';

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.75,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? Theme.of(context).colorScheme.primaryContainer
              : Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft:
                isUser ? const Radius.circular(16) : Radius.zero,
            bottomRight:
                isUser ? Radius.zero : const Radius.circular(16),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isUser ? '你' : 'AI',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: isUser
                    ? Theme.of(context).colorScheme.primary
                    : Theme.of(context).colorScheme.secondary,
              ),
            ),
            const SizedBox(height: 4),
            SelectableText(
              message.content,
              style: const TextStyle(fontSize: 15),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建底部输入区域（CLI 风格）
  Widget _buildInputArea() {
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
        left: 12,
        right: 12,
        top: 8,
        bottom: MediaQuery.of(context).padding.bottom + 8,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          // CLI 风格提示符
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(
              '> ',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.primary,
                fontFamily: 'monospace',
              ),
            ),
          ),
          // 输入框
          Expanded(
            child: TextField(
              controller: _messageController,
              focusNode: _focusNode,
              style: const TextStyle(
                fontSize: 16,
                fontFamily: 'monospace',
              ),
              decoration: const InputDecoration(
                hintText: '输入消息...',
                border: InputBorder.none,
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              ),
              maxLines: 5,
              minLines: 1,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          // 发送按钮
          IconButton(
            icon: Icon(
              Icons.send_rounded,
              color: Theme.of(context).colorScheme.primary,
            ),
            onPressed: _sendMessage,
          ),
        ],
      ),
    );
  }
}

/// 侧边栏历史对话内容组件
///
/// 显示历史对话摘要列表，支持搜索功能。
class _HistoryDrawerContent extends StatefulWidget {
  final void Function(String conversationId) onSelectConversation;
  final String? currentConversationId;

  const _HistoryDrawerContent({
    required this.onSelectConversation,
    this.currentConversationId,
  });

  @override
  State<_HistoryDrawerContent> createState() => _HistoryDrawerContentState();
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
        // 抽屉头部
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
                  Text(
                    '历史对话',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                ],
              ),
              const SizedBox(height: 12),
              // 侧边栏搜索框
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
                onChanged: (value) {
                  setState(() => _searchQuery = value);
                },
              ),
            ],
          ),
        ),
        // 对话列表
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
                    final isActive = conv.id == widget.currentConversationId;

                    return ListTile(
                      selected: isActive,
                      selectedTileColor: Theme.of(context)
                          .colorScheme
                          .primaryContainer
                          .withValues(alpha: 0.3),
                      leading: const Icon(Icons.chat, size: 20),
                      title: Text(
                        conv.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontWeight: isActive
                              ? FontWeight.bold
                              : FontWeight.normal,
                        ),
                      ),
                      subtitle: Text(
                        conv.preview,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 12),
                      ),
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

