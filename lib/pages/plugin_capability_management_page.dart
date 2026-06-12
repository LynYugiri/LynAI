import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/plugin.dart';
import '../providers/plugin_provider.dart';

/// 插件能力集中管理页。
class PluginCapabilityManagementPage extends StatefulWidget {
  const PluginCapabilityManagementPage({super.key});

  @override
  State<PluginCapabilityManagementPage> createState() =>
      _PluginCapabilityManagementPageState();
}

class _PluginCapabilityManagementPageState
    extends State<PluginCapabilityManagementPage> {
  final _queryController = TextEditingController();
  String _kind = 'all';
  String _pluginId = 'all';
  String _enabled = 'all';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<PluginProvider>();
    final entries = _filteredEntries(provider);
    return Scaffold(
      appBar: AppBar(title: const Text('插件能力'), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _queryController,
              decoration: const InputDecoration(
                prefixIcon: Icon(Icons.search),
                hintText: '搜索名称、描述、插件或标签',
                border: OutlineInputBorder(),
              ),
              onChanged: (_) => setState(() {}),
            ),
          ),
          _FilterBar(
            kind: _kind,
            pluginId: _pluginId,
            enabled: _enabled,
            plugins: provider.plugins,
            onKindChanged: (value) => setState(() => _kind = value),
            onPluginChanged: (value) => setState(() => _pluginId = value),
            onEnabledChanged: (value) => setState(() => _enabled = value),
          ),
          Expanded(
            child: entries.isEmpty
                ? const Center(child: Text('没有匹配的插件能力'))
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
                    itemCount: entries.length,
                    itemBuilder: (context, index) {
                      return _CapabilityCard(entry: entries[index]);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  List<_CapabilityEntry> _filteredEntries(PluginProvider provider) {
    final query = _queryController.text.trim().toLowerCase();
    final entries = <_CapabilityEntry>[];
    for (final plugin in provider.plugins) {
      if (_pluginId != 'all' && plugin.id != _pluginId) continue;
      for (final tool in plugin.manifest.tools) {
        entries.add(_CapabilityEntry.tool(plugin: plugin, tool: tool));
      }
      for (final function in plugin.manifest.functions) {
        entries.add(
          _CapabilityEntry.function(plugin: plugin, function: function),
        );
      }
      for (final skill in plugin.manifest.skills) {
        entries.add(_CapabilityEntry.skill(plugin: plugin, skill: skill));
      }
    }
    return entries
        .where((entry) {
          if (_kind != 'all' && entry.kind != _kind) return false;
          if (_enabled == 'enabled' && !entry.enabled) return false;
          if (_enabled == 'disabled' && entry.enabled) return false;
          if (query.isEmpty) return true;
          return entry.searchText.contains(query);
        })
        .toList(growable: false);
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.kind,
    required this.pluginId,
    required this.enabled,
    required this.plugins,
    required this.onKindChanged,
    required this.onPluginChanged,
    required this.onEnabledChanged,
  });

  final String kind;
  final String pluginId;
  final String enabled;
  final List<InstalledPlugin> plugins;
  final ValueChanged<String> onKindChanged;
  final ValueChanged<String> onPluginChanged;
  final ValueChanged<String> onEnabledChanged;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _Dropdown(
            value: kind,
            items: const {
              'all': '全部类型',
              'tool': 'Tools',
              'function': 'Functions',
              'skill': 'Skills',
            },
            onChanged: onKindChanged,
          ),
          const SizedBox(width: 8),
          _Dropdown(
            value: pluginId,
            items: {
              'all': '全部插件',
              for (final plugin in plugins) plugin.id: plugin.displayName,
            },
            onChanged: onPluginChanged,
          ),
          const SizedBox(width: 8),
          _Dropdown(
            value: enabled,
            items: const {'all': '全部状态', 'enabled': '已启用', 'disabled': '已禁用'},
            onChanged: onEnabledChanged,
          ),
        ],
      ),
    );
  }
}

class _Dropdown extends StatelessWidget {
  const _Dropdown({
    required this.value,
    required this.items,
    required this.onChanged,
  });

  final String value;
  final Map<String, String> items;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    return DropdownButton<String>(
      value: items.containsKey(value) ? value : items.keys.first,
      items: items.entries
          .map(
            (entry) =>
                DropdownMenuItem(value: entry.key, child: Text(entry.value)),
          )
          .toList(growable: false),
      onChanged: (value) {
        if (value != null) onChanged(value);
      },
    );
  }
}

class _CapabilityCard extends StatelessWidget {
  const _CapabilityCard({required this.entry});

  final _CapabilityEntry entry;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      child: SwitchListTile(
        value: entry.enabled,
        title: Text(entry.title),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(entry.qualifiedName),
            if (entry.description.isNotEmpty)
              Text(
                entry.description,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            Text(entry.plugin.displayName),
          ],
        ),
        secondary: CircleAvatar(
          backgroundColor: entry.color.withValues(alpha: 0.12),
          child: Icon(entry.icon, color: entry.color),
        ),
        onChanged: (value) => entry.setEnabled(context, value),
      ),
    );
  }
}

class _CapabilityEntry {
  final InstalledPlugin plugin;
  final String kind;
  final String name;
  final String title;
  final String description;
  final String searchText;
  final bool enabled;
  final IconData icon;
  final Color color;
  final Future<void> Function(BuildContext context, bool enabled) setEnabled;

  const _CapabilityEntry._({
    required this.plugin,
    required this.kind,
    required this.name,
    required this.title,
    required this.description,
    required this.searchText,
    required this.enabled,
    required this.icon,
    required this.color,
    required this.setEnabled,
  });

  String get qualifiedName => '${plugin.id}__$name';

  factory _CapabilityEntry.tool({
    required InstalledPlugin plugin,
    required PluginToolDefinition tool,
  }) {
    return _CapabilityEntry._(
      plugin: plugin,
      kind: 'tool',
      name: tool.name,
      title: tool.name,
      description: tool.description,
      searchText: _joinSearch([
        plugin.id,
        plugin.displayName,
        tool.name,
        tool.description,
        tool.handler,
      ]),
      enabled: plugin.enabledTools.contains(tool.name),
      icon: Icons.build_outlined,
      color: Colors.blue,
      setEnabled: (context, enabled) => context
          .read<PluginProvider>()
          .setToolEnabled(plugin.id, tool.name, enabled),
    );
  }

  factory _CapabilityEntry.function({
    required InstalledPlugin plugin,
    required PluginFunctionDefinition function,
  }) {
    return _CapabilityEntry._(
      plugin: plugin,
      kind: 'function',
      name: function.name,
      title: function.title.isEmpty ? function.name : function.title,
      description: function.description,
      searchText: _joinSearch([
        plugin.id,
        plugin.displayName,
        function.name,
        function.title,
        function.description,
        function.handler,
      ]),
      enabled: plugin.enabledFunctions.contains(function.name),
      icon: Icons.functions,
      color: Colors.deepPurple,
      setEnabled: (context, enabled) => context
          .read<PluginProvider>()
          .setFunctionEnabled(plugin.id, function.name, enabled),
    );
  }

  factory _CapabilityEntry.skill({
    required InstalledPlugin plugin,
    required PluginSkillDefinition skill,
  }) {
    return _CapabilityEntry._(
      plugin: plugin,
      kind: 'skill',
      name: skill.name,
      title: skill.title.isEmpty ? skill.name : skill.title,
      description: skill.description,
      searchText: _joinSearch([
        plugin.id,
        plugin.displayName,
        skill.name,
        skill.title,
        skill.description,
        skill.whenToUse,
        ...skill.tags,
      ]),
      enabled: plugin.enabledSkills.contains(skill.name),
      icon: Icons.auto_awesome_motion,
      color: Colors.orange,
      setEnabled: (context, enabled) => context
          .read<PluginProvider>()
          .setSkillEnabled(plugin.id, skill.name, enabled),
    );
  }

  static String _joinSearch(Iterable<String> values) {
    return values.join(' ').toLowerCase();
  }
}
