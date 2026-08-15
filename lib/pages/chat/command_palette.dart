import 'package:flutter/material.dart';

import '../../models/composer_reference.dart';
import '../../services/composer_selector_registry.dart';

/// 命令面板：从选择器注册表选取实体，生成类型化引用。
///
/// 首层列出所有选择器（内置笔记/待办与插件命令）；进入选择器后按文件夹分层
/// 导航，最终选中实体后通过 [onSelected] 回调产生 `ComposerSelectorValue` 与
/// 可选的模型覆盖 ID。
class ChatCommandPalette extends StatefulWidget {
  const ChatCommandPalette({
    super.key,
    required this.registry,
    required this.onSelected,
  });

  final ComposerSelectorRegistry registry;

  /// 选中一个实体；[modelId] 来自 selector 声明的模型覆盖（可空）。
  final void Function(ComposerSelectorValue value, String? modelId) onSelected;

  @override
  State<ChatCommandPalette> createState() => _ChatCommandPaletteState();
}

class _ChatCommandPaletteState extends State<ChatCommandPalette> {
  String? _activeSelector;
  final List<String> _path = [];
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final selector = _activeSelector == null
        ? null
        : widget.registry.selector(_activeSelector!);
    return Material(
      color: scheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _searchBar(selector),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 320),
            child: selector == null ? _sourceList() : _itemList(selector),
          ),
        ],
      ),
    );
  }

  Widget _searchBar(ComposerSelector? selector) {
    final scheme = Theme.of(context).colorScheme;
    final navigated = selector != null;
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 8, 8, 4),
      child: Row(
        children: [
          if (navigated)
            IconButton(
              tooltip: '返回',
              icon: const Icon(Icons.arrow_back),
              onPressed: _goBack,
            )
          else
            const Padding(
              padding: EdgeInsets.all(8),
              child: Icon(Icons.search, size: 20),
            ),
          Expanded(
            child: TextField(
              controller: _searchCtrl,
              autofocus: true,
              style: const TextStyle(fontSize: 14),
              decoration: InputDecoration(
                isDense: true,
                hintText: selector == null ? '搜索或选择类型' : '搜索${selector.title}',
                border: InputBorder.none,
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          IconButton(
            tooltip: '关闭',
            icon: Icon(Icons.close, size: 18, color: scheme.outline),
            onPressed: _close,
          ),
        ],
      ),
    );
  }

  void _close() {
    setState(() {
      _activeSelector = null;
      _path.clear();
      _searchCtrl.clear();
    });
  }

  void _goBack() {
    setState(() {
      if (_path.isNotEmpty) {
        _path.removeLast();
      } else {
        _activeSelector = null;
        _searchCtrl.clear();
      }
    });
  }

  Widget _sourceList() {
    final selectors = widget.registry.selectors.toList(growable: false);
    if (selectors.isEmpty) {
      return const Padding(
        padding: EdgeInsets.all(24),
        child: Text('没有可用的引用类型', textAlign: TextAlign.center),
      );
    }
    return ListView(
      shrinkWrap: true,
      children: [
        for (final selector in selectors)
          ListTile(
            dense: true,
            title: Text(
              selector.title.isEmpty ? selector.name : selector.title,
              style: const TextStyle(fontSize: 14),
            ),
            subtitle: selector.description.isEmpty
                ? null
                : Text(
                    selector.description,
                    style: const TextStyle(fontSize: 12),
                  ),
            trailing: const Icon(Icons.chevron_right, size: 20),
            onTap: () => setState(() {
              _activeSelector = selector.name;
              _path.clear();
            }),
          ),
      ],
    );
  }

  Widget _itemList(ComposerSelector selector) {
    return FutureBuilder<List<ComposerSelectorItem>>(
      future: selector.load(_searchCtrl.text, _path),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator()),
          );
        }
        final items = snapshot.data!;
        if (items.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(24),
            child: Text('没有匹配项', textAlign: TextAlign.center),
          );
        }
        return ListView(
          shrinkWrap: true,
          children: [
            for (final item in items)
              item.kind == ComposerSelectorItemKind.folder
                  ? ListTile(
                      dense: true,
                      leading: const Icon(Icons.folder_outlined, size: 20),
                      title: Text(
                        item.title,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: item.subtitle == null
                          ? null
                          : Text(
                              item.subtitle!,
                              style: const TextStyle(fontSize: 12),
                            ),
                      trailing: const Icon(Icons.chevron_right, size: 20),
                      onTap: () => setState(() {
                        _path.add(item.key.split(':').last);
                      }),
                    )
                  : ListTile(
                      dense: true,
                      leading: Icon(
                        _valueIcon(item.value?.type),
                        size: 20,
                      ),
                      title: Text(
                        item.title,
                        style: const TextStyle(fontSize: 14),
                      ),
                      subtitle: item.subtitle == null
                          ? null
                          : Text(
                              item.subtitle!,
                              style: const TextStyle(fontSize: 12),
                            ),
                      onTap: () {
                        final value = item.value;
                        if (value == null) return;
                        widget.onSelected(value, selector.modelId);
                      },
                    ),
          ],
        );
      },
    );
  }

  IconData _valueIcon(ComposerReferenceType? type) => switch (type) {
    ComposerReferenceType.note => Icons.note,
    ComposerReferenceType.notePage => Icons.description,
    ComposerReferenceType.task => Icons.check_circle_outline,
    ComposerReferenceType.taskList => Icons.checklist,
    ComposerReferenceType.pluginResource => Icons.extension,
    ComposerReferenceType.pluginSkill => Icons.auto_awesome,
    null => Icons.insert_link,
  };
}
