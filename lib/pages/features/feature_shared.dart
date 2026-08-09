import 'package:flutter/material.dart';

import '../../models/note.dart';
import '../../models/plugin.dart';

/// 笔记/导出长图的单页文本块长度上限。
const exportTextChunkLength = 2800;

/// 任务清单导出长图的单页权重上限。
const exportTodoPageWeight = 3200;

/// 插件功能页引用键前缀（`plugin:<pluginId>:<pageId>`）。
const pluginFeaturePrefix = 'plugin:';

/// 插件功能页引用。
///
/// 由插件 ID 与功能页 ID 组成，可序列化为 `plugin:<pluginId>:<pageId>` 键。
class PluginFeatureRef {
  final String pluginId;
  final String pageId;

  const PluginFeatureRef(this.pluginId, this.pageId);

  String get key => '$pluginFeaturePrefix$pluginId:$pageId';

  static PluginFeatureRef? tryParse(String value) {
    if (!value.startsWith(pluginFeaturePrefix)) return null;
    final rest = value.substring(pluginFeaturePrefix.length);
    final separator = rest.indexOf(':');
    if (separator <= 0 || separator == rest.length - 1) return null;
    final pluginId = rest.substring(0, separator);
    final pageId = rest.substring(separator + 1);
    if (pluginId.isEmpty || pageId.isEmpty) return null;
    return PluginFeatureRef(pluginId, pageId);
  }
}

/// 解析后的插件功能页。
///
/// 关联已安装插件实例与其功能页定义，用于路由到对应页面。
class ResolvedPluginFeature {
  final InstalledPlugin plugin;
  final PluginFeaturePageDefinition page;

  const ResolvedPluginFeature({required this.plugin, required this.page});
}

/// 搜索匹配器。
///
/// 支持字面搜索、正则搜索（`re:` 前缀或 `/pattern/flags` 语法），
/// 提供 [matches] 和 [allMatches] 两个查询接口。
class FeatureSearchMatcher {
  final String query;
  final bool caseSensitive;
  final String? regexError;
  final RegExp? _regex;

  FeatureSearchMatcher._({
    required this.query,
    required this.caseSensitive,
    required RegExp? regex,
    required this.regexError,
  }) : _regex = regex;

  factory FeatureSearchMatcher.literal(
    String query, {
    bool caseSensitive = false,
  }) {
    return FeatureSearchMatcher._(
      query: query,
      caseSensitive: caseSensitive,
      regex: null,
      regexError: null,
    );
  }

  // 解析 "re:" 前缀或 "/pattern/flags" 正则搜索语法。
  factory FeatureSearchMatcher.fromSearchSyntax(
    String query, {
    bool caseSensitive = false,
  }) {
    final parsed = _parseRegexSearch(query);
    if (parsed == null) return FeatureSearchMatcher.literal(query);
    try {
      return FeatureSearchMatcher._(
        query: query,
        caseSensitive: parsed.caseSensitive ?? caseSensitive,
        regex: RegExp(
          parsed.pattern,
          caseSensitive: parsed.caseSensitive ?? caseSensitive,
          multiLine: true,
        ),
        regexError: null,
      );
    } catch (e) {
      return FeatureSearchMatcher._(
        query: query,
        caseSensitive: caseSensitive,
        regex: null,
        regexError: '$e',
      );
    }
  }

  factory FeatureSearchMatcher.regex(
    String query, {
    required bool caseSensitive,
  }) {
    if (query.isEmpty) return FeatureSearchMatcher.literal(query);
    try {
      return FeatureSearchMatcher._(
        query: query,
        caseSensitive: caseSensitive,
        regex: RegExp(query, caseSensitive: caseSensitive, multiLine: true),
        regexError: null,
      );
    } catch (e) {
      return FeatureSearchMatcher._(
        query: query,
        caseSensitive: caseSensitive,
        regex: null,
        regexError: '$e',
      );
    }
  }

  bool get isEmpty => query.isEmpty;
  bool get isRegex => _regex != null;
  bool get hasError => regexError != null;

  bool matches(String text) {
    if (query.isEmpty) return true;
    final regex = _regex;
    if (regex != null) return regex.hasMatch(text);
    if (regexError != null) return false;
    if (caseSensitive) return text.contains(query);
    return text.toLowerCase().contains(query.toLowerCase());
  }

  // 返回正则匹配迭代器：有正则以正则，否则以转义后的字面匹配。
  Iterable<RegExpMatch> allMatches(String text) {
    final regex = _regex;
    if (query.isEmpty || regexError != null) return const Iterable.empty();
    if (regex != null) return regex.allMatches(text);
    final pattern = RegExp.escape(query);
    return RegExp(pattern, caseSensitive: caseSensitive).allMatches(text);
  }
}

/// 解析后的正则搜索参数。
///
/// 包含正则模式字符串及大小写敏感性标志。
class _ParsedRegexSearch {
  final String pattern;
  final bool? caseSensitive;

  const _ParsedRegexSearch(this.pattern, {this.caseSensitive});
}

_ParsedRegexSearch? _parseRegexSearch(String query) {
  final trimmed = query.trim();
  if (trimmed.startsWith('re:')) {
    final pattern = trimmed.substring(3).trim();
    return pattern.isEmpty ? null : _ParsedRegexSearch(pattern);
  }
  if (!trimmed.startsWith('/') || trimmed.length < 2) return null;
  final lastSlash = trimmed.lastIndexOf('/');
  if (lastSlash <= 0) return null;
  final pattern = trimmed.substring(1, lastSlash);
  if (pattern.isEmpty) return null;
  final flags = trimmed.substring(lastSlash + 1);
  final insensitive = flags.contains('i');
  return _ParsedRegexSearch(pattern, caseSensitive: !insensitive);
}

/// 功能页空状态。
class FeatureEmptyState extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const FeatureEmptyState({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 78,
              height: 78,
              decoration: BoxDecoration(
                color: scheme.primaryContainer.withValues(alpha: 0.45),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 38, color: scheme.primary),
            ),
            const SizedBox(height: 18),
            Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 8),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: TextStyle(color: scheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

/// 笔记两版本间的字符与行差异统计。
class NoteDiffStats {
  final int addedChars;
  final int removedChars;
  final int addedLines;
  final int removedLines;

  const NoteDiffStats({
    required this.addedChars,
    required this.removedChars,
    required this.addedLines,
    required this.removedLines,
  });

  bool get hasChanges => addedChars > 0 || removedChars > 0;
}

/// 差异行类型：上下文、新增、删除。
enum DiffLineType { context, added, removed }

/// 单行差异，含前后行号与文本。
class DiffLine {
  final DiffLineType type;
  final int? beforeLine;
  final int? afterLine;
  final String text;

  const DiffLine({
    required this.type,
    required this.beforeLine,
    required this.afterLine,
    required this.text,
  });
}

/// 格式化为 `yyyy-MM-dd HH:mm` 的本地时间字符串。
String formatNoteTime(DateTime value) {
  final year = value.year.toString().padLeft(4, '0');
  final month = value.month.toString().padLeft(2, '0');
  final day = value.day.toString().padLeft(2, '0');
  final hour = value.hour.toString().padLeft(2, '0');
  final minute = value.minute.toString().padLeft(2, '0');
  return '$year-$month-$day $hour:$minute';
}

/// 计算两版笔记内容的字符与行差异统计。
NoteDiffStats noteDiffStats(String before, String after) {
  final delta = NoteTextDelta.between(before, after);
  return NoteDiffStats(
    addedChars: delta.insertedText.length,
    removedChars: delta.deletedText.length,
    addedLines: _changedLineCount(delta.insertedText),
    removedLines: _changedLineCount(delta.deletedText),
  );
}

int _changedLineCount(String text) {
  if (text.isEmpty) return 0;
  return '\n'.allMatches(text).length + 1;
}

/// 生成“+N / -M 字符”差异摘要。
String noteDiffSummary(String before, String after) {
  final stats = noteDiffStats(before, after);
  if (!stats.hasChanges) return '无内容变化';
  if (stats.addedChars > 0 && stats.removedChars > 0) {
    return '+${stats.addedChars} / -${stats.removedChars} 字符';
  }
  if (stats.addedChars > 0) return '+${stats.addedChars} 字符';
  return '-${stats.removedChars} 字符';
}

/// 生成“+N / -M 行”差异摘要。
String noteLineDiffSummary(String before, String after) {
  final stats = noteDiffStats(before, after);
  if (!stats.hasChanges) return '行无变化';
  if (stats.addedLines > 0 && stats.removedLines > 0) {
    return '+${stats.addedLines} / -${stats.removedLines} 行';
  }
  if (stats.addedLines > 0) return '+${stats.addedLines} 行';
  return '-${stats.removedLines} 行';
}
