part of '../chat_page.dart';

/// 对话历史抽屉。
///
/// 按角色分组展示对话记录，支持搜索、置顶和管理操作。
class _HistoryDrawer extends StatefulWidget {
  final void Function(String) onSelect;
  final String? currentConvId;
  const _HistoryDrawer({required this.onSelect, this.currentConvId});

  @override
  State<_HistoryDrawer> createState() => _HistoryDrawerState();
}

sealed class _HistoryListItem {}

class _HistoryRoleHeaderItem extends _HistoryListItem {
  final String name;
  final Color? color;
  final String? roleId;

  _HistoryRoleHeaderItem(this.name, this.color, {this.roleId});
}

class _HistoryEmptyItem extends _HistoryListItem {
  final String text;

  _HistoryEmptyItem(this.text);
}

class _HistoryConversationItem extends _HistoryListItem {
  final Conversation conversation;
  final Color? roleColor;
  final ConversationSearchResult? result;

  _HistoryConversationItem(this.conversation, this.roleColor, {this.result});
}

class _HistoryDrawerState extends State<_HistoryDrawer> {
  final _searchCtrl = TextEditingController();
  Timer? _searchDebounce;
  String _q = '';

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 250), () {
      if (mounted) setState(() => _q = value);
    });
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
        .where((r) => r.conversation.roleId == currentRoleId)
        .toList();
    final otherResults = results
        .where((r) => r.conversation.roleId != currentRoleId)
        .toList();
    final otherRoleIds = otherResults
        .map((r) => r.conversation.roleId)
        .toSet()
        .toList();
    final items = <_HistoryListItem>[
      _HistoryRoleHeaderItem(currentRole.name, currentRole.themeColor),
      if (currentResults.isEmpty)
        _HistoryEmptyItem(_q.isEmpty ? '当前角色暂无对话' : '未找到匹配的对话'),
      for (final result in currentResults)
        _HistoryConversationItem(
          result.conversation,
          currentRole.themeColor,
          result: result,
        ),
      for (final roleId in otherRoleIds) ...[
        _HistoryRoleHeaderItem(
          roles
              .firstWhere(
                (role) => role.id == roleId,
                orElse: () => ChatRole.defaultRole().copyWith(name: roleId),
              )
              .name,
          roles
              .firstWhere(
                (role) => role.id == roleId,
                orElse: () => ChatRole.defaultRole().copyWith(name: roleId),
              )
              .themeColor,
          roleId: roleId,
        ),
        for (final result in otherResults.where(
          (r) => r.conversation.roleId == roleId,
        ))
          _HistoryConversationItem(
            result.conversation,
            roles
                .firstWhere(
                  (role) => role.id == roleId,
                  orElse: () => ChatRole.defaultRole().copyWith(name: roleId),
                )
                .themeColor,
            result: result,
          ),
      ],
    ];
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
                            _searchDebounce?.cancel();
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
                onChanged: _onSearchChanged,
              ),
            ],
          ),
        ),
        Expanded(
          child: results.isEmpty
              ? Center(
                  child: Text(
                    _q.isEmpty ? '暂无历史对话' : '无匹配结果',
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.outline,
                    ),
                  ),
                )
              : ListView.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    if (item is _HistoryRoleHeaderItem) {
                      final header = _roleHeader(
                        context,
                        item.name,
                        item.color,
                      );
                      if (item.roleId == null) return header;
                      return InkWell(
                        onTap: () => sp.selectRole(item.roleId!),
                        child: header,
                      );
                    }
                    if (item is _HistoryEmptyItem) {
                      return ListTile(
                        leading: const Icon(Icons.chat_bubble_outline),
                        title: Text(item.text),
                      );
                    }
                    final conversationItem = item as _HistoryConversationItem;
                    return _conversationTile(
                      context,
                      conversationItem.conversation,
                      conversationItem.roleColor,
                      conversationItem.result,
                    );
                  },
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
    ConversationSearchResult? result,
  ) {
    final active = c.id == widget.currentConvId;
    final matchType = result?.matchType ?? ConversationSearchMatchType.none;
    final snippet = result?.snippet ?? '';
    final showSnippetSubtitle =
        _q.isNotEmpty && snippet.isNotEmpty && result?.matchInTitle != true;
    final subtitle = showSnippetSubtitle
        ? '${_matchTypeLabel(matchType)}$snippet'
        : c.preview;
    return ListTile(
      selected: active,
      selectedTileColor: Theme.of(
        context,
      ).colorScheme.primaryContainer.withValues(alpha: 0.3),
      leading: Icon(Icons.chat, size: 20, color: roleColor),
      title: result?.matchInTitle == true
          ? _highlightText(
              c.title,
              result!.snippetRanges,
              TextStyle(
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            )
          : Text(
              c.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontWeight: active ? FontWeight.bold : FontWeight.normal,
              ),
            ),
      subtitle: showSnippetSubtitle
          ? _highlightText(
              subtitle,
              _shiftRanges(
                result!.snippetRanges,
                _matchTypeLabel(matchType).length,
              ),
              const TextStyle(fontSize: 12),
            )
          : Text(
              subtitle,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
      trailing: IconButton(
        icon: const Icon(Icons.delete_outline, size: 18),
        onPressed: () => _deleteDialog(context, c),
      ),
      onLongPress: () => _renameDialog(context, c),
      onTap: () {
        context.read<SettingsProvider>().selectRole(c.roleId);
        widget.onSelect(c.id);
      },
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

  Widget _highlightText(
    String text,
    List<ChatSearchRange> ranges,
    TextStyle? style,
  ) {
    if (ranges.isEmpty) {
      return Text(
        text,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: style,
      );
    }
    final scheme = Theme.of(context).colorScheme;
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
          style: TextStyle(
            color: scheme.onPrimary,
            backgroundColor: scheme.primary,
            fontWeight: FontWeight.w700,
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
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }

  void _renameDialog(BuildContext context, Conversation c) {
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
          onSubmitted: (_) => _saveConversationTitle(ctx, c, ctrl.text),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => _saveConversationTitle(ctx, c, ctrl.text),
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
    Conversation c,
    String value,
  ) {
    final title = value.replaceAll(RegExp(r'[\r\n]+'), ' ').trim();
    if (title.isEmpty) return;
    context.read<ConversationProvider>().updateConversationTitle(c.id, title);
    Navigator.pop(dialogContext);
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
            onPressed: () async {
              final provider = context.read<ConversationProvider>();
              try {
                await provider.deleteConversation(c.id);
                if (!ctx.mounted) return;
                Navigator.pop(ctx);
                if (c.id == widget.currentConvId) widget.onSelect('');
              } catch (e) {
                if (!ctx.mounted) return;
                ScaffoldMessenger.of(
                  ctx,
                ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
              }
            },
            child: Text('删除', style: TextStyle(color: Colors.red[400])),
          ),
        ],
      ),
    );
  }
}
