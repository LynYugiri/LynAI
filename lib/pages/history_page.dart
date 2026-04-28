import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/conversation_provider.dart';

/// 对话历史列表页面
///
/// 功能：
/// - 展示所有历史对话，显示摘要标题和对话开头预览
/// - 顶部搜索栏，支持搜索标题和消息内容
/// - 搜索结果高亮显示匹配文本
/// - 点击对话跳转到聊天页面继续对话
/// - 长按可删除对话
class HistoryPage extends StatefulWidget {
  /// 当用户点击某个对话时的回调，传入对话ID
  final void Function(String conversationId) onConversationTap;

  const HistoryPage({super.key, required this.onConversationTap});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<HistoryPage> {
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

    return Scaffold(
      appBar: AppBar(
        title: const Text('对话历史'),
        centerTitle: true,
      ),
      body: Column(
        children: [
          // 搜索栏
          Padding(
            padding: const EdgeInsets.all(12.0),
            child: TextField(
              controller: _searchController,
              decoration: InputDecoration(
                hintText: '搜索对话标题或内容...',
                prefixIcon: const Icon(Icons.search),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                filled: true,
                fillColor: Theme.of(context)
                    .colorScheme
                    .surfaceContainerHighest
                    .withValues(alpha: 0.3),
              ),
              onChanged: (value) {
                setState(() => _searchQuery = value);
              },
            ),
          ),
          // 对话列表
          Expanded(
            child: results.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _searchQuery.isEmpty
                              ? Icons.chat_bubble_outline
                              : Icons.search_off,
                          size: 64,
                          color: Colors.grey[400],
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty ? '暂无对话记录' : '未找到匹配的对话',
                          style: TextStyle(
                            fontSize: 16,
                            color: Colors.grey[600],
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    itemCount: results.length,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    itemBuilder: (context, index) {
                      final result = results[index];
                      final conversation = result['conversation'];
                      final matchInTitle =
                          result['matchInTitle'] as bool? ?? false;
                      final matchContent =
                          result['matchContent'] as String? ?? '';

                      return _buildConversationItem(
                        conversation,
                        matchInTitle,
                        matchContent,
                        provider,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  /// 构建单个对话列表项
  Widget _buildConversationItem(
    dynamic conversation,
    bool matchInTitle,
    String matchContent,
    ConversationProvider provider,
  ) {
    return Card(
      margin: const EdgeInsets.symmetric(vertical: 4),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor:
              Theme.of(context).colorScheme.primaryContainer,
          child: const Icon(Icons.chat),
        ),
        // 标题：显示对话摘要，搜索时高亮匹配部分
        title: _searchQuery.isNotEmpty && matchInTitle
            ? _buildHighlightedText(
                conversation.title,
                _searchQuery,
                Theme.of(context).textTheme.titleMedium,
              )
            : Text(
                conversation.title,
                style: Theme.of(context).textTheme.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        // 副标题：显示对话开头预览，搜索时高亮匹配部分
        subtitle: _searchQuery.isNotEmpty && !matchInTitle
            ? _buildHighlightedText(
                matchContent.isNotEmpty
                    ? matchContent
                    : conversation.preview,
                _searchQuery,
                Theme.of(context).textTheme.bodySmall,
              )
            : Text(
                conversation.preview,
                style: Theme.of(context).textTheme.bodySmall,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: Text(
          _formatDate(conversation.updatedAt),
          style: Theme.of(context).textTheme.bodySmall,
        ),
        onTap: () {
          widget.onConversationTap(conversation.id);
        },
        onLongPress: () {
          _showDeleteDialog(context, provider, conversation);
        },
      ),
    );
  }

  /// 构建高亮文本
  ///
  /// 将搜索关键词在文本中的匹配部分用黄色背景高亮显示。
  /// [text] 原始文本
  /// [query] 搜索关键词
  /// [baseStyle] 基础文本样式
  Widget _buildHighlightedText(
      String text, String query, TextStyle? baseStyle) {
    if (query.isEmpty) return Text(text, style: baseStyle);

    final lowerText = text.toLowerCase();
    final lowerQuery = query.toLowerCase();
    final spans = <TextSpan>[];
    int start = 0;

    while (true) {
      final index = lowerText.indexOf(lowerQuery, start);
      if (index == -1) {
        // 没有更多匹配，添加剩余文本
        spans.add(TextSpan(text: text.substring(start)));
        break;
      }
      // 添加匹配前的普通文本
      if (index > start) {
        spans.add(TextSpan(text: text.substring(start, index)));
      }
      // 添加高亮的匹配文本
      spans.add(TextSpan(
        text: text.substring(index, index + query.length),
        style: TextStyle(
          backgroundColor: Colors.yellow.withValues(alpha: 0.5),
          fontWeight: FontWeight.bold,
          color: Colors.black87,
        ),
      ));
      start = index + query.length;
    }

    return RichText(
      text: TextSpan(
        style: baseStyle ?? DefaultTextStyle.of(context).style,
        children: spans,
      ),
      maxLines:
          baseStyle == Theme.of(context).textTheme.titleMedium ? 1 : 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  /// 格式化日期为可读字符串
  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final diff = now.difference(date);

    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }

  /// 显示删除确认对话框
  void _showDeleteDialog(
    BuildContext context,
    ConversationProvider provider,
    dynamic conversation,
  ) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('删除对话'),
        content: Text('确定要删除"${conversation.title}"吗？'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () {
              provider.deleteConversation(conversation.id);
              Navigator.pop(ctx);
            },
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}

