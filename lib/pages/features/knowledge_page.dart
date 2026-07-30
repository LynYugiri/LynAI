part of '../feature_page.dart';

class _KnowledgePage extends StatefulWidget {
  const _KnowledgePage({super.key});

  @override
  State<_KnowledgePage> createState() => _KnowledgePageState();
}

class _KnowledgePageState extends State<_KnowledgePage> {
  final _searchController = TextEditingController();
  String? _selectedBaseId;
  String? _selectedEntryId;
  String? _categoryFilterId;
  bool _compactDetail = false;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool handleBack() {
    if (!_compactDetail) return false;
    setState(() => _compactDetail = false);
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<KnowledgeProvider>();
    final bases = provider.knowledgeBases;
    final base = _resolveBase(provider, bases);
    final categories = base == null
        ? const <KnowledgeCategory>[]
        : provider.categoriesForBase(base.id);
    final categoryFilterId = _resolveCategoryFilter(categories);
    final allEntries = base == null
        ? const <KnowledgeEntry>[]
        : provider.entriesForBase(base.id);
    final query = _searchController.text.trim().toLowerCase();
    final entries = allEntries.where((entry) {
      if (categoryFilterId != null && entry.categoryId != categoryFilterId) {
        return false;
      }
      return query.isEmpty ||
          entry.title.toLowerCase().contains(query) ||
          entry.content.toLowerCase().contains(query);
    }).toList();
    final entry = _resolveEntry(provider, entries);

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= 980) {
          return Row(
            children: [
              SizedBox(width: 260, child: _basePane(provider, bases, base)),
              const VerticalDivider(width: 1),
              SizedBox(
                width: 330,
                child: _entryPane(
                  provider,
                  base,
                  categories,
                  categoryFilterId,
                  entries,
                  entry,
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(child: _detailPane(provider, base, entry)),
            ],
          );
        }

        if (_compactDetail && base != null && entry != null) {
          return _detailPane(provider, base, entry, compact: true);
        }
        return Column(
          children: [
            _compactHeader(provider, bases, base),
            Expanded(
              child: base == null
                  ? _emptyBases(context, provider)
                  : _entryPane(
                      provider,
                      base,
                      categories,
                      categoryFilterId,
                      entries,
                      entry,
                      compact: true,
                    ),
            ),
          ],
        );
      },
    );
  }

  KnowledgeBase? _resolveBase(
    KnowledgeProvider provider,
    List<KnowledgeBase> bases,
  ) {
    final selected = _selectedBaseId;
    if (selected != null) {
      final value = provider.knowledgeBaseById(selected);
      if (value != null) return value;
    }
    return bases.isEmpty ? null : bases.first;
  }

  String? _resolveCategoryFilter(List<KnowledgeCategory> categories) {
    final selected = _categoryFilterId;
    if (selected == null || categories.any((item) => item.id == selected)) {
      return selected;
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _categoryFilterId != selected) return;
      setState(() => _categoryFilterId = null);
    });
    return null;
  }

  KnowledgeEntry? _resolveEntry(
    KnowledgeProvider provider,
    List<KnowledgeEntry> entries,
  ) {
    final selected = _selectedEntryId;
    if (selected != null) {
      final value = provider.entryById(selected);
      if (value != null && entries.any((item) => item.id == value.id)) {
        return value;
      }
    }
    return entries.isEmpty ? null : entries.first;
  }

  Widget _basePane(
    KnowledgeProvider provider,
    List<KnowledgeBase> bases,
    KnowledgeBase? selected,
  ) {
    return Column(
      children: [
        _paneHeader(
          context,
          title: '知识库',
          action: IconButton(
            tooltip: '新建知识库',
            icon: const Icon(Icons.add),
            onPressed: () => _createBase(provider),
          ),
        ),
        Expanded(
          child: bases.isEmpty
              ? _emptyBases(context, provider)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: bases.length,
                  itemBuilder: (context, index) {
                    final base = bases[index];
                    final active = selected?.id == base.id;
                    return Card(
                      elevation: active ? 1 : 0,
                      color: active
                          ? Theme.of(context).colorScheme.primaryContainer
                          : null,
                      child: ListTile(
                        selected: active,
                        leading: Icon(
                          base.enabled
                              ? Icons.local_library_outlined
                              : Icons.visibility_off_outlined,
                        ),
                        title: Row(
                          children: [
                            Flexible(
                              child: Text(
                                base.name,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (provider.isBuiltInKnowledgeBase(base))
                              const Padding(
                                padding: EdgeInsets.only(left: 8),
                                child: Chip(
                                  label: Text('内置'),
                                  visualDensity: VisualDensity.compact,
                                ),
                              ),
                          ],
                        ),
                        subtitle: Text(
                          '${provider.entriesForBase(base.id).length} 个条目',
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                unawaited(_editBase(provider, base));
                                break;
                              case 'toggle':
                                unawaited(
                                  _updateBase(
                                    provider,
                                    base.copyWith(enabled: !base.enabled),
                                  ),
                                );
                                break;
                              case 'restore':
                                unawaited(_restoreBuiltInBase(provider));
                                break;
                              case 'delete':
                                unawaited(_deleteBase(provider, base));
                                break;
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('编辑'),
                            ),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Text(base.enabled ? '停用' : '启用'),
                            ),
                            if (provider.isBuiltInKnowledgeBase(base))
                              const PopupMenuItem(
                                value: 'restore',
                                child: Text('恢复默认'),
                              )
                            else ...[
                              const PopupMenuDivider(),
                              const PopupMenuItem(
                                value: 'delete',
                                child: Text('删除知识库'),
                              ),
                            ],
                          ],
                        ),
                        onTap: () => setState(() {
                          _selectedBaseId = base.id;
                          _selectedEntryId = null;
                          _categoryFilterId = null;
                          _compactDetail = false;
                        }),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _entryPane(
    KnowledgeProvider provider,
    KnowledgeBase? base,
    List<KnowledgeCategory> categories,
    String? categoryFilterId,
    List<KnowledgeEntry> entries,
    KnowledgeEntry? selected, {
    bool compact = false,
  }) {
    if (base == null) return _emptyBases(context, provider);
    return Column(
      children: [
        _paneHeader(
          context,
          title: base.name,
          subtitle: base.description,
          action: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                tooltip: '管理类别',
                icon: const Icon(Icons.category_outlined),
                onPressed: () => _manageCategories(provider, base),
              ),
              IconButton(
                tooltip: '新建条目',
                icon: const Icon(Icons.add),
                onPressed: () => _createEntry(provider, base, categories),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _searchController,
                  decoration: const InputDecoration(
                    hintText: '搜索标题或内容',
                    prefixIcon: Icon(Icons.search),
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                  onChanged: (_) => setState(() {}),
                ),
              ),
              const SizedBox(width: 8),
              DropdownButton<String?>(
                value: categoryFilterId,
                hint: const Text('全部类别'),
                items: [
                  const DropdownMenuItem(value: null, child: Text('全部类别')),
                  for (final category in categories)
                    DropdownMenuItem(
                      value: category.id,
                      child: Text(category.name),
                    ),
                ],
                onChanged: (value) => setState(() => _categoryFilterId = value),
              ),
            ],
          ),
        ),
        Expanded(
          child: entries.isEmpty
              ? _emptyEntries(context, provider, base, categories)
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 12),
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    final category = entry.categoryId == null
                        ? null
                        : provider.categoryById(entry.categoryId!);
                    return Card(
                      child: ListTile(
                        leading: CircleAvatar(
                          child: Icon(
                            entry.enabled
                                ? Icons.description_outlined
                                : Icons.visibility_off_outlined,
                            size: 20,
                          ),
                        ),
                        title: Text(
                          entry.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          category?.name ?? '未分类',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: PopupMenuButton<String>(
                          onSelected: (value) {
                            switch (value) {
                              case 'edit':
                                unawaited(
                                  _editEntry(provider, base, categories, entry),
                                );
                                break;
                              case 'toggle':
                                unawaited(
                                  _updateEntry(
                                    provider,
                                    entry.copyWith(enabled: !entry.enabled),
                                  ),
                                );
                                break;
                              case 'delete':
                                unawaited(_deleteEntry(provider, entry));
                                break;
                            }
                          },
                          itemBuilder: (_) => [
                            const PopupMenuItem(
                              value: 'edit',
                              child: Text('编辑'),
                            ),
                            PopupMenuItem(
                              value: 'toggle',
                              child: Text(entry.enabled ? '停用' : '启用'),
                            ),
                            const PopupMenuDivider(),
                            const PopupMenuItem(
                              value: 'delete',
                              child: Text('删除'),
                            ),
                          ],
                        ),
                        onTap: () => setState(() {
                          _selectedEntryId = entry.id;
                          _compactDetail = compact;
                        }),
                      ),
                    );
                  },
                ),
        ),
      ],
    );
  }

  Widget _detailPane(
    KnowledgeProvider provider,
    KnowledgeBase? base,
    KnowledgeEntry? entry, {
    bool compact = false,
  }) {
    if (base == null) return _emptyBases(context, provider);
    if (entry == null) {
      return const Center(child: Text('选择一个条目查看详情'));
    }
    final category = entry.categoryId == null
        ? null
        : provider.categoryById(entry.categoryId!);
    final explanations = provider.explanationsForEntry(entry.id);
    final sources = provider.sourcesForEntry(entry.id);
    return Column(
      children: [
        _paneHeader(
          context,
          title: entry.title,
          subtitle: category?.name ?? '未分类',
          leading: compact
              ? IconButton(
                  tooltip: '返回条目列表',
                  icon: const Icon(Icons.arrow_back),
                  onPressed: () => setState(() => _compactDetail = false),
                )
              : null,
          action: IconButton(
            tooltip: '编辑条目',
            icon: const Icon(Icons.edit_outlined),
            onPressed: () => _editEntry(
              provider,
              base,
              provider.categoriesForBase(base.id),
              entry,
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _detailSection(
                context,
                icon: Icons.subject,
                title: '内容',
                child: entry.content.trim().isEmpty
                    ? const Text('暂无内容')
                    : MarkdownWithLatex(
                        content: entry.content,
                        onTapKnowledgeAnnotation: null,
                        onExplainSelection: null,
                      ),
              ),
              const SizedBox(height: 12),
              _detailSection(
                context,
                icon: Icons.auto_awesome_outlined,
                title: '解释',
                child: explanations.isEmpty
                    ? const Text('暂无解释')
                    : Column(
                        children: [
                          for (final explanation in explanations)
                            _explanationTile(explanation),
                        ],
                      ),
              ),
              const SizedBox(height: 12),
              _detailSection(
                context,
                icon: Icons.link,
                title: '来源',
                child: sources.isEmpty
                    ? const Text('暂无来源')
                    : Column(
                        children: [
                          for (final source in sources) _sourceTile(source),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _compactHeader(
    KnowledgeProvider provider,
    List<KnowledgeBase> bases,
    KnowledgeBase? selected,
  ) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              key: ValueKey(selected?.id),
              initialValue: selected?.id,
              decoration: const InputDecoration(
                labelText: '知识库',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: bases
                  .map(
                    (base) => DropdownMenuItem(
                      value: base.id,
                      child: Text(
                        base.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  )
                  .toList(),
              onChanged: (value) => setState(() {
                _selectedBaseId = value;
                _selectedEntryId = null;
                _categoryFilterId = null;
                _compactDetail = false;
              }),
            ),
          ),
          IconButton(
            tooltip: '新建知识库',
            icon: const Icon(Icons.add),
            onPressed: () => _createBase(provider),
          ),
          if (selected != null)
            IconButton(
              tooltip: '知识库操作',
              icon: const Icon(Icons.more_vert),
              onPressed: () => _showBaseActions(provider, selected),
            ),
        ],
      ),
    );
  }

  Widget _paneHeader(
    BuildContext context, {
    required String title,
    String? subtitle,
    Widget? leading,
    Widget? action,
  }) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 10),
      child: Row(
        children: [
          ?leading,
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (subtitle?.trim().isNotEmpty == true)
                  Text(
                    subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
              ],
            ),
          ),
          ?action,
        ],
      ),
    );
  }

  Widget _emptyBases(BuildContext context, KnowledgeProvider provider) {
    return _emptyState(
      context,
      icon: Icons.local_library_outlined,
      title: '还没有知识库',
      message: '创建一个知识库，开始整理条目、解释和来源。',
      actionLabel: '新建知识库',
      onAction: () => _createBase(provider),
    );
  }

  Widget _emptyEntries(
    BuildContext context,
    KnowledgeProvider provider,
    KnowledgeBase base,
    List<KnowledgeCategory> categories,
  ) {
    return _emptyState(
      context,
      icon: Icons.description_outlined,
      title: '暂无条目',
      message: '可以先配置类别，也可以直接创建第一条知识。',
      actionLabel: '新建条目',
      onAction: () => _createEntry(provider, base, categories),
    );
  }

  Widget _emptyState(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String message,
    required String actionLabel,
    required VoidCallback onAction,
  }) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 12),
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: onAction,
              icon: const Icon(Icons.add),
              label: Text(actionLabel),
            ),
          ],
        ),
      ),
    );
  }

  Widget _detailSection(
    BuildContext context, {
    required IconData icon,
    required String title,
    required Widget child,
  }) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 20),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: Theme.of(
                    context,
                  ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
                ),
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }

  Widget _explanationTile(KnowledgeExplanation explanation) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      title: explanation.title.trim().isEmpty ? null : Text(explanation.title),
      subtitle: MarkdownWithLatex(
        content: explanation.content,
        onTapKnowledgeAnnotation: null,
        onExplainSelection: null,
      ),
    );
  }

  Widget _sourceTile(KnowledgeSource source) {
    final details = [
      if (source.url?.trim().isNotEmpty == true) source.url!.trim(),
      if (source.note?.trim().isNotEmpty == true) source.note!.trim(),
    ];
    final url = source.url?.trim();
    final copyText = [
      source.title,
      ...details,
    ].where((value) => value.isNotEmpty).join('\n');
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(
        url == null || url.isEmpty ? Icons.link : Icons.open_in_new,
        size: 20,
      ),
      title: Text(source.title.trim().isEmpty ? '未命名来源' : source.title),
      subtitle: details.isEmpty ? null : Text(details.join('\n')),
      trailing: Wrap(
        spacing: 4,
        children: [
          if (url != null && url.isNotEmpty)
            IconButton(
              tooltip: '打开来源',
              icon: const Icon(Icons.open_in_new),
              onPressed: () => _openSource(url),
            ),
          IconButton(
            tooltip: '复制来源',
            icon: const Icon(Icons.copy_outlined),
            onPressed: () async {
              try {
                await Clipboard.setData(ClipboardData(text: copyText));
                if (mounted) showShortSnackBar(context, '已复制来源');
              } catch (error, stackTrace) {
                if (mounted) {
                  showErrorSnackBar(
                    context,
                    '复制来源失败',
                    details: '$error\n$stackTrace',
                  );
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Future<void> _createBase(KnowledgeProvider provider) =>
      _editBase(provider, null);

  Future<void> _editBase(
    KnowledgeProvider provider,
    KnowledgeBase? base,
  ) async {
    final nameController = TextEditingController(text: base?.name ?? '');
    final descriptionController = TextEditingController(
      text: base?.description ?? '',
    );
    var enabled = base?.enabled ?? true;
    final result = await showDialog<(String, String, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(base == null ? '新建知识库' : '编辑知识库'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 420,
              maxHeight: MediaQuery.sizeOf(context).height * .7,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  TextField(
                    controller: descriptionController,
                    decoration: const InputDecoration(labelText: '描述（可选）'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final name = nameController.text.trim();
                if (name.isEmpty) return;
                Navigator.pop(context, (
                  name,
                  descriptionController.text.trim(),
                  enabled,
                ));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    _disposeControllersLater([nameController, descriptionController]);
    if (result == null || !mounted) return;
    await _runOperation(() async {
      if (base == null) {
        final id = await provider.addKnowledgeBase(
          name: result.$1,
          description: result.$2.isEmpty ? null : result.$2,
          enabled: result.$3,
        );
        if (mounted) setState(() => _selectedBaseId = id);
      } else {
        await provider.updateKnowledgeBase(
          base.copyWith(
            name: result.$1,
            description: result.$2,
            enabled: result.$3,
          ),
        );
      }
    }, '保存知识库失败');
  }

  Future<void> _updateBase(KnowledgeProvider provider, KnowledgeBase base) =>
      _runOperation(() => provider.updateKnowledgeBase(base), '更新知识库失败');

  Future<void> _deleteBase(
    KnowledgeProvider provider,
    KnowledgeBase base,
  ) async {
    final confirmed = await _confirmDelete(
      title: '删除“${base.name}”？',
      message: '其中的类别、条目、解释和来源也会被删除。',
    );
    if (!confirmed) return;
    final succeeded = await _runOperation(
      () => provider.deleteKnowledgeBase(base.id),
      '删除知识库失败',
    );
    if (!succeeded) return;
    if (!mounted) return;
    setState(() {
      if (_selectedBaseId == base.id) _selectedBaseId = null;
      _selectedEntryId = null;
      _compactDetail = false;
    });
  }

  Future<void> _createEntry(
    KnowledgeProvider provider,
    KnowledgeBase base,
    List<KnowledgeCategory> categories,
  ) => _editEntry(provider, base, categories, null);

  Future<void> _editEntry(
    KnowledgeProvider provider,
    KnowledgeBase base,
    List<KnowledgeCategory> categories,
    KnowledgeEntry? entry,
  ) async {
    final titleController = TextEditingController(text: entry?.title ?? '');
    final contentController = TextEditingController(text: entry?.content ?? '');
    String? categoryId = entry?.categoryId;
    var enabled = entry?.enabled ?? true;
    final result = await showDialog<(String, String, String?, bool)>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(entry == null ? '新建条目' : '编辑条目'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 520,
              maxHeight: MediaQuery.sizeOf(context).height * .72,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: titleController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '标题'),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  const SizedBox(height: 8),
                  DropdownButtonFormField<String?>(
                    initialValue: categoryId,
                    decoration: const InputDecoration(labelText: '类别'),
                    items: [
                      const DropdownMenuItem(value: null, child: Text('未分类')),
                      for (final category in categories)
                        DropdownMenuItem(
                          value: category.id,
                          child: Text(category.name),
                        ),
                    ],
                    onChanged: (value) {
                      setDialogState(() => categoryId = value);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: contentController,
                    minLines: 5,
                    maxLines: 10,
                    decoration: const InputDecoration(
                      labelText: '内容',
                      alignLabelWithHint: true,
                      border: OutlineInputBorder(),
                    ),
                  ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final title = titleController.text.trim();
                if (title.isEmpty) return;
                Navigator.pop(context, (
                  title,
                  contentController.text.trim(),
                  categoryId,
                  enabled,
                ));
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
    _disposeControllersLater([titleController, contentController]);
    if (result == null || !mounted) return;
    await _runOperation(() async {
      if (entry == null) {
        final id = await provider.addEntry(
          knowledgeBaseId: base.id,
          categoryId: result.$3,
          title: result.$1,
          content: result.$2,
          enabled: result.$4,
        );
        if (mounted) setState(() => _selectedEntryId = id);
      } else {
        await provider.updateEntry(
          entry.copyWith(
            categoryId: result.$3,
            title: result.$1,
            content: result.$2,
            enabled: result.$4,
          ),
        );
      }
    }, '保存条目失败');
  }

  Future<void> _updateEntry(KnowledgeProvider provider, KnowledgeEntry entry) =>
      _runOperation(() => provider.updateEntry(entry), '更新条目失败');

  Future<void> _deleteEntry(
    KnowledgeProvider provider,
    KnowledgeEntry entry,
  ) async {
    final confirmed = await _confirmDelete(
      title: '删除“${entry.title}”？',
      message: '条目的解释和来源也会被删除。',
    );
    if (!confirmed) return;
    final succeeded = await _runOperation(
      () => provider.deleteEntry(entry.id),
      '删除条目失败',
    );
    if (!succeeded) return;
    if (!mounted) return;
    setState(() {
      if (_selectedEntryId == entry.id) _selectedEntryId = null;
      _compactDetail = false;
    });
  }

  Future<bool> _confirmDelete({
    required String title,
    required String message,
  }) async {
    return await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text(title),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('删除'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _showBaseActions(
    KnowledgeProvider provider,
    KnowledgeBase base,
  ) async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑知识库'),
              onTap: () => Navigator.pop(context, 'edit'),
            ),
            ListTile(
              leading: Icon(
                base.enabled ? Icons.visibility_off : Icons.visibility,
              ),
              title: Text(base.enabled ? '停用知识库' : '启用知识库'),
              onTap: () => Navigator.pop(context, 'toggle'),
            ),
            if (provider.isBuiltInKnowledgeBase(base))
              ListTile(
                leading: const Icon(Icons.restore),
                title: const Text('恢复默认'),
                onTap: () => Navigator.pop(context, 'restore'),
              )
            else
              ListTile(
                leading: const Icon(Icons.delete_outline),
                title: const Text('删除知识库'),
                onTap: () => Navigator.pop(context, 'delete'),
              ),
          ],
        ),
      ),
    );
    switch (action) {
      case 'edit':
        await _editBase(provider, base);
        break;
      case 'toggle':
        await _updateBase(provider, base.copyWith(enabled: !base.enabled));
        break;
      case 'restore':
        await _restoreBuiltInBase(provider);
        break;
      case 'delete':
        await _deleteBase(provider, base);
        break;
      case null:
        break;
    }
  }

  Future<void> _restoreBuiltInBase(KnowledgeProvider provider) =>
      _runOperation(provider.restoreBuiltInKnowledgeBase, '恢复内置知识库失败');

  Future<void> _openSource(String value) async {
    try {
      final uri = Uri.parse(value);
      if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
        throw StateError('无法打开链接');
      }
    } catch (error, stackTrace) {
      if (mounted) {
        showErrorSnackBar(context, '打开来源失败', details: '$error\n$stackTrace');
      }
    }
  }

  Future<bool> _runOperation(
    Future<void> Function() operation,
    String message,
  ) async {
    try {
      await operation();
      return true;
    } catch (error, stackTrace) {
      if (mounted) {
        showErrorSnackBar(context, message, details: '$error\n$stackTrace');
      }
      return false;
    }
  }

  void _disposeControllersLater(Iterable<TextEditingController> controllers) {
    Future<void>.delayed(kThemeAnimationDuration, () {
      for (final controller in controllers) {
        controller.dispose();
      }
    });
  }

  Future<void> _manageCategories(
    KnowledgeProvider provider,
    KnowledgeBase base,
  ) async {
    await showDialog<void>(
      context: context,
      builder: (context) => _KnowledgeCategoryManagerDialog(
        provider: provider,
        knowledgeBase: base,
      ),
    );
  }
}

class _KnowledgeCategoryManagerDialog extends StatefulWidget {
  const _KnowledgeCategoryManagerDialog({
    required this.provider,
    required this.knowledgeBase,
  });

  final KnowledgeProvider provider;
  final KnowledgeBase knowledgeBase;

  @override
  State<_KnowledgeCategoryManagerDialog> createState() =>
      _KnowledgeCategoryManagerDialogState();
}

class _KnowledgeCategoryManagerDialogState
    extends State<_KnowledgeCategoryManagerDialog> {
  static const _colors = [
    '#5B8DEF',
    '#8B6FE8',
    '#D45D79',
    '#E08A3E',
    '#3D9B78',
    '#607D8B',
  ];

  @override
  Widget build(BuildContext context) {
    final categories = widget.provider.categoriesForBase(
      widget.knowledgeBase.id,
    );
    return AlertDialog(
      title: Row(
        children: [
          const Expanded(child: Text('类别管理')),
          IconButton(
            tooltip: '新建类别',
            icon: const Icon(Icons.add),
            onPressed: () => _editCategory(),
          ),
        ],
      ),
      content: SizedBox(
        width: math.min(680, MediaQuery.sizeOf(context).width - 80),
        height: math.min(480, MediaQuery.sizeOf(context).height * .72),
        child: categories.isEmpty
            ? Center(
                child: FilledButton.icon(
                  onPressed: () => _editCategory(),
                  icon: const Icon(Icons.add),
                  label: const Text('创建第一个类别'),
                ),
              )
            : ListView.separated(
                itemCount: categories.length,
                separatorBuilder: (_, _) => const Divider(height: 1),
                itemBuilder: (context, index) {
                  final category = categories[index];
                  final data = _categoryData(category);
                  return ListTile(
                    leading: CircleAvatar(
                      backgroundColor: _parseColor(data.color),
                      child: const Icon(
                        Icons.label_outline,
                        color: Colors.white,
                      ),
                    ),
                    title: Row(
                      children: [
                        Flexible(child: Text(category.name)),
                        if (widget.provider.isBuiltInCategory(category))
                          const Padding(
                            padding: EdgeInsets.only(left: 8),
                            child: Chip(
                              label: Text('内置'),
                              visualDensity: VisualDensity.compact,
                            ),
                          ),
                      ],
                    ),
                    subtitle: Text(
                      [
                        '标识：${data.alias}',
                        category.enabled ? '已启用' : '已停用',
                        if (data.autoAnnotate) '自动标注',
                      ].join(' · '),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    trailing: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        IconButton(
                          tooltip: '编辑',
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => _editCategory(category),
                        ),
                        if (widget.provider.isBuiltInCategory(category))
                          IconButton(
                            tooltip: '恢复默认',
                            icon: const Icon(Icons.restore),
                            onPressed: () => _restoreCategory(),
                          )
                        else
                          IconButton(
                            tooltip: '删除',
                            icon: const Icon(Icons.delete_outline),
                            onPressed: () => _deleteCategory(category),
                          ),
                      ],
                    ),
                    onTap: () => _editCategory(category),
                  );
                },
              ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('完成'),
        ),
      ],
    );
  }

  Future<void> _editCategory([KnowledgeCategory? category]) async {
    final original = category == null ? null : _categoryData(category);
    final nameController = TextEditingController(text: category?.name ?? '');
    final aliasController = TextEditingController(text: original?.alias ?? '');
    final ruleController = TextEditingController(text: original?.rule ?? '');
    final promptController = TextEditingController(
      text: original?.prompt ?? '',
    );
    ModelConfigProvider? modelProvider;
    try {
      modelProvider = context.read<ModelConfigProvider>();
    } on ProviderNotFoundException {
      modelProvider = null;
    }
    final models =
        modelProvider?.enabledModelsByCategory(ModelConfig.categoryChat) ??
        const <ModelConfig>[];
    var color = original?.color ?? _colors.first;
    var autoAnnotate = original?.autoAnnotate ?? false;
    var enabled = category?.enabled ?? true;
    var modelConfigId = category?.modelConfigId;
    String? formError;
    var saving = false;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          title: Text(category == null ? '新建类别' : '编辑类别'),
          content: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.sizeOf(context).height * .72,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextField(
                    controller: nameController,
                    autofocus: true,
                    decoration: const InputDecoration(labelText: '名称'),
                  ),
                  TextField(
                    controller: aliasController,
                    decoration: const InputDecoration(
                      labelText: 'alias',
                      hintText: '例如 poetry、cet6',
                      helperText: '全局唯一；小写字母开头，仅可含小写字母、数字、_、-',
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text('唯一标注语法：[[alias:示例文本]]'),
                  ),
                  TextField(
                    controller: ruleController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '标注规则',
                      helperText: '只描述哪些词句需要标注，不要填写输出格式或其他语法。',
                      alignLabelWithHint: true,
                    ),
                  ),
                  TextField(
                    controller: promptController,
                    minLines: 2,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      labelText: '解释提示词',
                      alignLabelWithHint: true,
                    ),
                  ),
                  if (models.isNotEmpty)
                    DropdownButtonFormField<String?>(
                      initialValue:
                          models.any((model) => model.id == modelConfigId)
                          ? modelConfigId
                          : null,
                      decoration: const InputDecoration(labelText: '解释模型'),
                      items: [
                        const DropdownMenuItem(
                          value: null,
                          child: Text('跟随默认模型'),
                        ),
                        for (final model in models)
                          DropdownMenuItem(
                            value: model.id,
                            child: Text('${model.name} · ${model.modelName}'),
                          ),
                      ],
                      onChanged: (value) =>
                          setDialogState(() => modelConfigId = value),
                    ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '颜色',
                      style: Theme.of(context).textTheme.labelLarge,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 10,
                    runSpacing: 8,
                    children: [
                      for (final value in _colors)
                        InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => setDialogState(() => color = value),
                          child: CircleAvatar(
                            radius: 18,
                            backgroundColor: _parseColor(value),
                            child: color == value
                                ? const Icon(
                                    Icons.check,
                                    color: Colors.white,
                                    size: 20,
                                  )
                                : null,
                          ),
                        ),
                    ],
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('自动标注'),
                    value: autoAnnotate,
                    onChanged: (value) =>
                        setDialogState(() => autoAnnotate = value),
                  ),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('启用'),
                    value: enabled,
                    onChanged: (value) => setDialogState(() => enabled = value),
                  ),
                  if (formError != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Align(
                        alignment: Alignment.centerLeft,
                        child: Text(
                          formError!,
                          style: TextStyle(
                            color: Theme.of(context).colorScheme.error,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: saving ? null : () => Navigator.pop(context),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: saving
                  ? null
                  : () async {
                      final name = nameController.text.trim();
                      final alias = aliasController.text.trim().toLowerCase();
                      String? error;
                      if (name.isEmpty) {
                        error = '请输入类别名称';
                      } else if (!isValidKnowledgeCategoryAlias(alias)) {
                        error = 'alias 格式无效';
                      } else {
                        final existing = widget.provider.categoryByAlias(alias);
                        if (existing != null && existing.id != category?.id) {
                          error = 'alias 已被其他类别使用';
                        }
                      }
                      if (error != null) {
                        setDialogState(() => formError = error);
                        return;
                      }
                      setDialogState(() {
                        saving = true;
                        formError = null;
                      });
                      try {
                        if (category == null) {
                          await widget.provider.addCategory(
                            knowledgeBaseId: widget.knowledgeBase.id,
                            name: name,
                            alias: alias,
                            annotationRule: ruleController.text.trim(),
                            explanationPrompt: promptController.text.trim(),
                            colorValue: _parseColor(color).toARGB32(),
                            autoAnnotate: autoAnnotate,
                            enabled: enabled,
                            modelConfigId: modelConfigId,
                          );
                        } else {
                          await widget.provider.updateCategory(
                            category.copyWith(
                              name: name,
                              alias: alias,
                              annotationRule: ruleController.text.trim(),
                              explanationPrompt: promptController.text.trim(),
                              colorValue: _parseColor(color).toARGB32(),
                              autoAnnotate: autoAnnotate,
                              enabled: enabled,
                              modelConfigId: modelConfigId,
                            ),
                          );
                        }
                        if (dialogContext.mounted) Navigator.pop(dialogContext);
                      } catch (error) {
                        if (dialogContext.mounted) {
                          setDialogState(() {
                            saving = false;
                            formError = error.toString();
                          });
                          showErrorSnackBar(
                            dialogContext,
                            '保存类别失败',
                            details: error.toString(),
                          );
                        }
                      }
                    },
              child: saving
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('保存'),
            ),
          ],
        ),
      ),
    );
    Future<void>.delayed(kThemeAnimationDuration, () {
      nameController.dispose();
      aliasController.dispose();
      ruleController.dispose();
      promptController.dispose();
    });
    if (mounted) setState(() {});
  }

  Future<void> _deleteCategory(KnowledgeCategory category) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('删除“${category.name}”？'),
        content: const Text('该类别下的条目会保留，并变为未分类。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('删除'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    try {
      await widget.provider.deleteCategory(category.id);
    } catch (error, stackTrace) {
      if (mounted) {
        showErrorSnackBar(context, '删除类别失败', details: '$error\n$stackTrace');
      }
      return;
    }
    if (mounted) setState(() {});
  }

  Future<void> _restoreCategory() async {
    try {
      await widget.provider.restoreBuiltInCategory();
    } catch (error, stackTrace) {
      if (mounted) {
        showErrorSnackBar(context, '恢复内置类别失败', details: '$error\n$stackTrace');
      }
      return;
    }
    if (mounted) setState(() {});
  }

  _KnowledgeCategoryFormData _categoryData(KnowledgeCategory category) {
    return _KnowledgeCategoryFormData(
      name: category.name,
      alias: category.alias,
      rule: category.annotationRule,
      prompt: category.explanationPrompt,
      color:
          '#${(category.colorValue & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}',
      autoAnnotate: category.autoAnnotate,
      enabled: category.enabled,
    );
  }

  Color _parseColor(String value) {
    final hex = value.replaceFirst('#', '');
    final parsed = int.tryParse(hex, radix: 16);
    return parsed == null
        ? const Color(0xFF5B8DEF)
        : Color(0xFF000000 | parsed);
  }
}

class _KnowledgeCategoryFormData {
  const _KnowledgeCategoryFormData({
    required this.name,
    required this.alias,
    required this.rule,
    required this.prompt,
    required this.color,
    required this.autoAnnotate,
    required this.enabled,
  });

  final String name;
  final String alias;
  final String rule;
  final String prompt;
  final String color;
  final bool autoAnnotate;
  final bool enabled;
}
