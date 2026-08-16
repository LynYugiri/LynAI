import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/knowledge_entry.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import 'api_service.dart';

/// 一张由模型生成、尚未保存的记忆卡片。
final class GeneratedMemoryCard {
  const GeneratedMemoryCard({
    required this.front,
    required this.back,
    this.hint,
  });

  final String front;
  final String back;
  final String? hint;

  Map<String, dynamic> toJson() => {
    'front': front,
    'back': back,
    if (hint != null && hint!.trim().isNotEmpty) 'hint': hint,
  };
}

/// 加载记忆卡片生成 Skill 正文，作为卡片页与对话侧共享的质量规则。
final class MemoryCardSkillPrompt {
  static const pluginId = 'mobile-agent-skills';
  static const skillPath = 'skills/memory_card_generation.md';
  static const assetPath =
      'assets/plugins/mobile-agent-skills/defaults/skills/memory_card_generation.md';

  static const fallbackPrompt = '''
你是记忆卡片生成助手。根据用户提供的知识条目制作间隔重复记忆卡片。
- 一张卡片只承载一个原子知识点；正面是问题/提示/挖空，反面是答案/解释。
- 答案必须来自原文或可验证推导，不编造；信息不足时宁少勿多。
- 保留 Markdown 与 LaTeX。
''';

  Future<String> load({PluginProvider? plugins}) async {
    if (plugins != null) {
      try {
        final content = await plugins.readFile(pluginId, skillPath);
        if (content.trim().isNotEmpty) return content.trim();
      } catch (_) {
        // 回退到内置资产。
      }
    }
    try {
      final content = await rootBundle.loadString(assetPath);
      if (content.trim().isNotEmpty) return content.trim();
    } catch (_) {
      // 回退到内置最小提示词。
    }
    return fallbackPrompt;
  }
}

/// 记忆卡片生成服务。
///
/// 从选中的知识库条目中提取问答对，返回预览列表；不会直接持久化。
final class MemoryCardGenerationService {
  MemoryCardGenerationService({
    required ApiService api,
    required ModelConfigProvider modelConfigs,
    required SettingsProvider settings,
    PluginProvider? plugins,
  }) : _api = api,
       _modelConfigs = modelConfigs,
       _settings = settings,
       _plugins = plugins;

  static const int defaultTargetCount = 20;
  static const int maxTargetCount = 50;
  static const int maxEntryChars = 6000;
  static const int maxBatchChars = 20000;
  static const int maxFrontChars = 500;
  static const int maxBackChars = 3000;
  static const int maxHintChars = 500;

  final ApiService _api;
  final ModelConfigProvider _modelConfigs;
  final SettingsProvider _settings;
  final PluginProvider? _plugins;

  ModelConfig? selectModel(String? modelConfigId) {
    final models = _modelConfigs.enabledModelsByCategory(
      ModelConfig.categoryChat,
    );
    if (models.isEmpty) return null;
    final categoryModel = _findModel(models, modelConfigId);
    if (categoryModel != null) return categoryModel;
    final role = _settings.currentRole;
    final roleModel = _findModel(models, role.modelId);
    if (roleModel != null) {
      final modelName = role.modelName?.trim();
      return modelName == null || modelName.isEmpty
          ? roleModel
          : roleModel.copyWith(modelName: modelName);
    }
    final recent = _findModel(models, _settings.settings.lastChatModelId);
    return recent ?? models.first;
  }

  Future<List<GeneratedMemoryCard>> generate({
    required List<KnowledgeEntry> entries,
    int targetCount = defaultTargetCount,
    String? modelConfigId,
    String extraPrompt = '',
  }) async {
    final count = targetCount.clamp(1, maxTargetCount).toInt();
    if (entries.isEmpty) throw ArgumentError.value(entries, 'entries', '不能为空');
    final model = selectModel(modelConfigId);
    if (model == null) throw StateError('没有可用的聊天模型，请先配置模型');

    final skillPrompt = await MemoryCardSkillPrompt().load(plugins: _plugins);
    final batches = _batches(entries);
    final cards = <GeneratedMemoryCard>[];
    final seen = <String>{};
    for (final batch in batches) {
      final response = await _api.sendChatRequest(model, [
        {
          'role': 'system',
          'content':
              '$skillPrompt\n\n请输出 JSON，格式为 {"cards":[{"front":"...","back":"...","hint":"..."}]}。'
              '不要输出 Markdown code fence，不要输出 JSON 以外的内容。'
              '${extraPrompt.trim().isEmpty ? '' : '\n\n用户补充要求：\n${extraPrompt.trim()}'}',
        },
        {
          'role': 'user',
          'content':
              '请从以下知识库条目中制作记忆卡片，目标数量约 $count 张。\n\n${_formatBatch(batch)}',
        },
      ]);
      for (final card in _parseCards(response.content)) {
        if (cards.length >= count) break;
        final key = '${card.front.trim()}\u0000${card.back.trim()}';
        if (!seen.add(key)) continue;
        cards.add(card);
      }
      if (cards.length >= count) break;
    }
    if (cards.isEmpty) throw StateError('模型未返回有效卡片');
    return cards;
  }

  List<List<KnowledgeEntry>> _batches(List<KnowledgeEntry> entries) {
    final batches = <List<KnowledgeEntry>>[];
    var current = <KnowledgeEntry>[];
    var chars = 0;
    for (final entry in entries) {
      final content = _entryContent(entry);
      final size = entry.title.length + content.length;
      if (current.isNotEmpty && chars + size > maxBatchChars) {
        batches.add(List.of(current));
        current = [];
        chars = 0;
      }
      current.add(entry);
      chars += size;
    }
    if (current.isNotEmpty) batches.add(List.of(current));
    return batches;
  }

  String _entryContent(KnowledgeEntry entry) {
    final content = entry.content.length <= maxEntryChars
        ? entry.content
        : '${entry.content.substring(0, maxEntryChars)}\n...(内容已截断)';
    return content;
  }

  String _formatBatch(List<KnowledgeEntry> batch) {
    final buffer = StringBuffer();
    for (final entry in batch) {
      buffer.writeln('---');
      buffer.writeln('条目 ID: ${entry.id}');
      buffer.writeln('标题: ${entry.title}');
      buffer.writeln(_entryContent(entry));
    }
    return buffer.toString();
  }

  List<GeneratedMemoryCard> _parseCards(String content) {
    final text = _extractJsonObject(content.trim());
    if (text == null) return const [];
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) return const [];
      final rawCards = decoded['cards'];
      if (rawCards is! List) return const [];
      final cards = <GeneratedMemoryCard>[];
      for (final raw in rawCards) {
        if (raw is! Map) continue;
        final front = raw['front']?.toString().trim() ?? '';
        final back = raw['back']?.toString().trim() ?? '';
        if (front.isEmpty || back.isEmpty) continue;
        if (front.length > maxFrontChars || back.length > maxBackChars) {
          continue;
        }
        final hint = raw['hint']?.toString().trim();
        cards.add(
          GeneratedMemoryCard(
            front: front,
            back: back,
            hint: hint == null || hint.isEmpty
                ? null
                : (hint.length > maxHintChars ? hint.substring(0, maxHintChars) : hint),
          ),
        );
      }
      return cards;
    } catch (_) {
      return const [];
    }
  }

  static String? _extractJsonObject(String text) {
    final fenced = RegExp(r'```(?:json)?\s*([\s\S]*?)```').firstMatch(text);
    if (fenced != null) return fenced.group(1)?.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  ModelConfig? _findModel(List<ModelConfig> models, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}
