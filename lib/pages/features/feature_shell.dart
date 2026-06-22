part of '../feature_page.dart';

class _AddMenuItem {
  final String value;
  final IconData icon;
  final String label;

  const _AddMenuItem(this.value, this.icon, this.label);
}

class _AddMenuButton extends StatelessWidget {
  final List<_AddMenuItem> items;
  final ValueChanged<String> onSelected;

  const _AddMenuButton({required this.items, required this.onSelected});

  @override
  Widget build(BuildContext context) {
    return FloatingActionButton(
      heroTag: null,
      tooltip: '新建',
      onPressed: () => _showMenu(context),
      child: const Icon(Icons.add),
    );
  }

  Future<void> _showMenu(BuildContext context) async {
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final box = context.findRenderObject() as RenderBox;
    final offset = box.localToGlobal(Offset.zero, ancestor: overlay);
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        offset.dx,
        offset.dy,
        overlay.size.width - offset.dx - box.size.width,
        overlay.size.height - offset.dy - box.size.height,
      ),
      items: items
          .map(
            (item) => PopupMenuItem(
              value: item.value,
              child: ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                leading: Icon(item.icon),
                title: Text(item.label),
              ),
            ),
          )
          .toList(),
    );
    if (value != null) onSelected(value);
  }
}

class _HistoryList extends StatelessWidget {
  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final void Function(String conversationId) onConversationTap;
  final VoidCallback onRoleChanged;

  const _HistoryList({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onConversationTap,
    required this.onRoleChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cp = context.watch<ConversationProvider>();
    final sp = context.watch<SettingsProvider>();
    final roles = sp.settings.roles;
    final currentRoleId = sp.settings.currentRoleId;
    final current = roles.firstWhere(
      (r) => r.id == currentRoleId,
      orElse: ChatRole.defaultRole,
    );
    final results = cp.searchConversations(searchQuery);
    final currentResults = results
        .where((r) => r.conversation.roleId == currentRoleId)
        .toList();
    final otherResults = results
        .where((r) => r.conversation.roleId != currentRoleId)
        .toList();
    final otherRoleIds = otherResults
        .map((r) => r.conversation.roleId)
        .toSet()
        .toList();
    final hasAnyConversation = cp.conversations.isNotEmpty;

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 6),
          child: Row(
            children: [
              Expanded(child: _searchBox(context)),
              const SizedBox(width: 8),
              PopupMenuButton<String>(
                tooltip: '切换角色',
                initialValue: currentRoleId,
                onSelected: (id) {
                  sp.selectRole(id);
                },
                itemBuilder: (_) => roles
                    .map((r) => PopupMenuItem(value: r.id, child: Text(r.name)))
                    .toList(),
                child: Chip(label: Text(current.name)),
              ),
            ],
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            children: [
              if (!hasAnyConversation && searchQuery.isEmpty)
                _historyEmptyState(context, current.name),
              _sectionTitle(context, current.name, current.themeColor),
              if (currentResults.isEmpty) _emptyTile(searchQuery),
              for (final r in currentResults)
                _conversationItem(context, r, cp, current.themeColor),
              for (final roleId in otherRoleIds) ...[
                Builder(
                  builder: (context) {
                    final role = roles.firstWhere(
                      (r) => r.id == roleId,
                      orElse: () =>
                          ChatRole.defaultRole().copyWith(name: roleId),
                    );
                    final list = otherResults
                        .where((r) => r.conversation.roleId == roleId)
                        .toList();
                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        InkWell(
                          onTap: () {
                            sp.selectRole(role.id);
                          },
                          child: _sectionTitle(
                            context,
                            role.name,
                            role.themeColor,
                          ),
                        ),
                        for (final result in list)
                          _conversationItem(
                            context,
                            result,
                            cp,
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

  Widget _historyEmptyState(BuildContext context, String roleName) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(4, 8, 4, 12),
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: scheme.primaryContainer.withValues(alpha: 0.28),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: scheme.primary.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.auto_awesome, color: scheme.primary),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '开始使用 $roleName',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '在底部切到“对话”发送第一条消息，这里会自动沉淀历史记录。',
                  style: TextStyle(color: scheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _searchBox(BuildContext context) {
    return TextField(
      controller: searchController,
      decoration: InputDecoration(
        hintText: '搜索对话标题或内容...',
        prefixIcon: const Icon(Icons.search),
        suffixIcon: searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear),
                onPressed: () {
                  searchController.clear();
                  onSearchChanged('');
                },
              )
            : null,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
      ),
      onChanged: onSearchChanged,
    );
  }

  Widget _sectionTitle(BuildContext context, String title, Color? color) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 4),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: color ?? Theme.of(context).colorScheme.primary,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  Widget _emptyTile(String query) {
    return ListTile(
      leading: const Icon(Icons.chat_bubble_outline),
      title: Text(query.isEmpty ? '当前角色暂无对话' : '未找到匹配的对话'),
      subtitle: query.isEmpty ? const Text('切换到对话页后开始聊天') : null,
    );
  }

  Widget _conversationItem(
    BuildContext context,
    ConversationSearchResult result,
    ConversationProvider provider,
    Color? roleColor,
  ) {
    final conversation = result.conversation;
    final matchInTitle = result.matchInTitle;
    final matchContent = result.snippet;
    final matchLabel = _matchTypeLabel(result.matchType);
    final color = roleColor ?? Theme.of(context).colorScheme.primary;
    return Card(
      color: roleColor == null ? null : color.withValues(alpha: 0.06),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.14),
          child: Icon(Icons.chat, color: color),
        ),
        title: searchQuery.isNotEmpty && matchInTitle
            ? _highlight(
                context,
                conversation.title,
                result.snippetRanges,
                Theme.of(context).textTheme.titleMedium,
              )
            : Text(
                conversation.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
        subtitle: searchQuery.isNotEmpty && !matchInTitle
            ? _highlight(
                context,
                matchContent.isNotEmpty
                    ? '$matchLabel$matchContent'
                    : conversation.preview,
                _shiftRanges(result.snippetRanges, matchLabel.length),
                Theme.of(context).textTheme.bodySmall,
              )
            : Text(
                conversation.preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
        trailing: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(_formatDate(conversation.updatedAt)),
            IconButton(
              tooltip: '删除',
              icon: const Icon(Icons.delete_outline, size: 18),
              onPressed: () => _deleteDialog(context, provider, conversation),
            ),
          ],
        ),
        onTap: () {
          context.read<SettingsProvider>().selectRole(conversation.roleId);
          onConversationTap(conversation.id);
        },
        onLongPress: () => _renameDialog(context, provider, conversation),
      ),
    );
  }

  String _matchTypeLabel(ConversationSearchMatchType type) {
    return switch (type) {
      ConversationSearchMatchType.message => '正文：',
      ConversationSearchMatchType.attachment => '附件：',
      _ => '',
    };
  }

  List<ChatSearchRange> _shiftRanges(List<ChatSearchRange> ranges, int offset) {
    if (offset == 0) return ranges;
    return ranges
        .map(
          (range) => ChatSearchRange(
            start: range.start + offset,
            end: range.end + offset,
          ),
        )
        .toList(growable: false);
  }

  Widget _highlight(
    BuildContext context,
    String text,
    List<ChatSearchRange> ranges,
    TextStyle? style,
  ) {
    if (searchQuery.isEmpty || ranges.isEmpty) return Text(text, style: style);
    final spans = <TextSpan>[];
    var start = 0;
    for (final range in ranges) {
      if (range.start < start || range.end > text.length) continue;
      if (range.start > start) {
        spans.add(TextSpan(text: text.substring(start, range.start)));
      }
      spans.add(
        TextSpan(
          text: text.substring(range.start, range.end),
          style: const TextStyle(
            backgroundColor: Colors.yellow,
            color: Colors.black,
          ),
        ),
      );
      start = range.end;
    }
    if (start < text.length) spans.add(TextSpan(text: text.substring(start)));
    return RichText(
      text: TextSpan(
        style: style ?? DefaultTextStyle.of(context).style,
        children: spans,
      ),
      maxLines: 2,
      overflow: TextOverflow.ellipsis,
    );
  }

  String _formatDate(DateTime date) {
    final diff = DateTime.now().difference(date);
    if (diff.inMinutes < 1) return '刚刚';
    if (diff.inHours < 1) return '${diff.inMinutes}分钟前';
    if (diff.inDays < 1) return '${diff.inHours}小时前';
    if (diff.inDays < 7) return '${diff.inDays}天前';
    return '${date.month}/${date.day}';
  }

  void _renameDialog(
    BuildContext context,
    ConversationProvider provider,
    Conversation c,
  ) {
    final ctrl = TextEditingController(text: c.title);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('重命名对话'),
        content: TextField(
          controller: ctrl,
          autofocus: true,
          maxLength: 40,
          decoration: const InputDecoration(
            labelText: '对话标题',
            border: OutlineInputBorder(),
          ),
          textInputAction: TextInputAction.done,
          onSubmitted: (_) =>
              _saveConversationTitle(ctx, provider, c, ctrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () =>
                _saveConversationTitle(ctx, provider, c, ctrl.text),
            child: const Text('保存'),
          ),
        ],
      ),
    ).then((_) {
      WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
    });
  }

  void _saveConversationTitle(
    BuildContext dialogContext,
    ConversationProvider provider,
    Conversation c,
    String value,
  ) {
    final title = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (title.isEmpty) return;
    provider.updateConversationTitle(c.id, title);
    Navigator.pop(dialogContext);
  }

  void _deleteDialog(
    BuildContext context,
    ConversationProvider provider,
    Conversation c,
  ) {
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
            onPressed: () async {
              try {
                await provider.deleteConversation(c.id);
                if (ctx.mounted) Navigator.pop(ctx);
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
              }
            },
            child: const Text('删除'),
          ),
        ],
      ),
    );
  }
}
