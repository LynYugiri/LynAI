import 'dart:convert';

import 'package:flutter/services.dart' show rootBundle;

import '../models/knowledge_entry.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';
import '../providers/plugin_provider.dart';
import '../providers/settings_provider.dart';
import 'api_service.dart';

const _generatedMemoryCardUnset = Object();

/// 一张由模型生成、尚未保存的记忆卡片。
final class GeneratedMemoryCard {
  const GeneratedMemoryCard({
    required this.front,
    required this.back,
    this.hint,
    this.sourceEntryId,
  });

  final String front;
  final String back;
  final String? hint;

  /// 来源知识条目 ID；与输入条目一一对应。
  final String? sourceEntryId;

  Map<String, dynamic> toJson() => {
    'front': front,
    'back': back,
    if (hint != null && hint!.trim().isNotEmpty) 'hint': hint,
    if (sourceEntryId != null && sourceEntryId!.trim().isNotEmpty)
      'sourceEntryId': sourceEntryId,
  };

  GeneratedMemoryCard copyWith({
    String? front,
    String? back,
    Object? hint = _generatedMemoryCardUnset,
    Object? sourceEntryId = _generatedMemoryCardUnset,
  }) => GeneratedMemoryCard(
    front: front ?? this.front,
    back: back ?? this.back,
    hint: identical(hint, _generatedMemoryCardUnset)
        ? this.hint
        : hint as String?,
    sourceEntryId: identical(sourceEntryId, _generatedMemoryCardUnset)
        ? this.sourceEntryId
        : sourceEntryId as String?,
  );
}

/// 生成结果及按条目维度的覆盖核账。
final class MemoryCardGenerationResult {
  const MemoryCardGenerationResult({
    required this.cards,
    required this.coveredEntryIds,
    required this.missingEntryIds,
    required this.warnings,
  });

  final List<GeneratedMemoryCard> cards;

  /// 已产出卡片的来源条目 ID。
  final List<String> coveredEntryIds;

  /// 本次输入中未产出任何有效卡片的条目 ID。
  final List<String> missingEntryIds;

  /// 解析与去重过程中产生的非致命警告。
  final List<String> warnings;
}

/// 加载记忆卡片生成 Skill 正文，作为卡片页与对话侧共享的质量规则。
final class MemoryCardSkillPrompt {
  static const pluginId = 'mobile-agent-skills';
  static const skillPath = 'skills/memory_card_generation.md';
  static const assetPath =
      'assets/plugins/mobile-agent-skills/defaults/skills/memory_card_generation.md';

  static const fallbackPrompt = '''
你是记忆卡片生成助手。根据用户提供的知识条目制作间隔重复记忆卡片。
- 每个已选知识条目生成 1 张卡片，卡片数量必须等于输入条目数量。
- 一张卡片只承载一个原子知识点；正面是问题/提示/挖空，反面是答案/解释。
- 答案必须来自原文或可验证推导，不编造；信息不足时宁少勿多。
- 每张卡片必须填写 sourceEntryId，且只能使用输入中给出的条目 ID。
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
/// 从选中的知识库条目中提取问答对。固定规则：**每个条目生成 1 张卡片**，
/// 返回的每张卡片必须携带来源条目 ID，调用方据此做覆盖核账。
/// 本服务只返回预览结果，不会直接持久化。
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

  static const int maxEntriesPerRun = 200;
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

  Future<MemoryCardGenerationResult> generate({
    required List<KnowledgeEntry> entries,
    String? modelConfigId,
    String extraPrompt = '',
    void Function(int done, int total)? onBatchProgress,
    bool Function()? isCancelled,
  }) async {
    if (entries.isEmpty) {
      throw ArgumentError.value(entries, 'entries', '不能为空');
    }
    if (entries.length > maxEntriesPerRun) {
      throw StateError('一次最多为 $maxEntriesPerRun 个条目生成卡片，请减少选择');
    }
    final model = selectModel(modelConfigId);
    if (model == null) throw StateError('没有可用的聊天模型，请先配置模型');

    final skillPrompt = await MemoryCardSkillPrompt().load(plugins: _plugins);
    final batches = _batches(entries);
    final cards = <GeneratedMemoryCard>[];
    final warnings = <String>[];
    final seenCardKeys = <String>{};
    final seenEntryIds = <String>{};
    var processedEntries = 0;

    for (var batchIndex = 0; batchIndex < batches.length; batchIndex++) {
      if (isCancelled?.call() ?? false) {
        throw StateError('生成已取消');
      }
      final batch = batches[batchIndex];
      final allowedEntryIds = {for (final entry in batch) entry.id};
      final response = await _api.sendChatRequest(model, [
        {
          'role': 'system',
          'content':
              '$skillPrompt\n\n请输出 JSON，格式为 {"cards":[{"front":"...","back":"...","hint":"...","sourceEntryId":"条目 ID"}]}。'
              'cards 数组长度必须等于下面给出的条目数量，且每张卡片只对应一个条目。'
              '不要输出 Markdown code fence，不要输出 JSON 以外的内容。'
              '${extraPrompt.trim().isEmpty ? '' : '\n\n用户补充要求：\n${extraPrompt.trim()}'}',
        },
        {
          'role': 'user',
          'content':
              '请为下面 ${batch.length} 个知识条目各生成 1 张卡片，共 ${batch.length} 张。\n\n'
              '${_formatBatch(batch)}',
        },
      ]);
      final parsed = _parseCards(
        response.content,
        allowedEntryIds: allowedEntryIds,
        batchIndex: batchIndex,
      );
      warnings.addAll(parsed.warnings);
      for (final card in parsed.cards) {
        final key = '${card.front.trim()}\u0000${card.back.trim()}';
        if (!seenCardKeys.add(key)) {
          warnings.add('丢弃重复卡片：${_cardSummary(card.front)}');
          continue;
        }
        final sourceEntryId = card.sourceEntryId;
        if (sourceEntryId != null && !seenEntryIds.add(sourceEntryId)) {
          warnings.add('条目 $sourceEntryId 返回了多张卡片，仅保留第一张');
          continue;
        }
        cards.add(card);
      }
      processedEntries += batch.length;
      onBatchProgress?.call(processedEntries, entries.length);
    }

    final coveredEntryIds = cards
        .map((card) => card.sourceEntryId)
        .whereType<String>()
        .toSet();
    final missingEntryIds = entries
        .map((entry) => entry.id)
        .where((id) => !coveredEntryIds.contains(id))
        .toList(growable: false);

    if (cards.isEmpty) {
      final detail = warnings.isEmpty ? '模型没有返回有效卡片' : warnings.join('；');
      throw StateError('模型未返回有效卡片：$detail');
    }
    return MemoryCardGenerationResult(
      cards: List.unmodifiable(cards),
      coveredEntryIds: List.unmodifiable(coveredEntryIds),
      missingEntryIds: List.unmodifiable(missingEntryIds),
      warnings: List.unmodifiable(warnings),
    );
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

  _ParsedCards _parseCards(
    String content, {
    required Set<String> allowedEntryIds,
    required int batchIndex,
  }) {
    final warnings = <String>[];
    final text = _extractJsonObject(content.trim());
    if (text == null) {
      return _ParsedCards(const [], ['第 ${batchIndex + 1} 批：模型未返回 JSON']);
    }
    try {
      final decoded = jsonDecode(text);
      if (decoded is! Map) {
        return _ParsedCards(const [], ['第 ${batchIndex + 1} 批：返回的 JSON 不是对象']);
      }
      final rawCards = decoded['cards'];
      if (rawCards is! List) {
        return _ParsedCards(const [], [
          '第 ${batchIndex + 1} 批：返回的 JSON 缺少 cards 数组',
        ]);
      }
      final cards = <GeneratedMemoryCard>[];
      for (final raw in rawCards) {
        if (raw is! Map) continue;
        final sourceEntryId = raw['sourceEntryId']?.toString().trim() ?? '';
        if (sourceEntryId.isEmpty) {
          warnings.add('第 ${batchIndex + 1} 批：丢弃 1 张缺少 sourceEntryId 的卡片');
          continue;
        }
        if (!allowedEntryIds.contains(sourceEntryId)) {
          warnings.add('第 ${batchIndex + 1} 批：丢弃来源不属于本次条目的卡片 $sourceEntryId');
          continue;
        }
        final front = raw['front']?.toString().trim() ?? '';
        final back = raw['back']?.toString().trim() ?? '';
        if (front.isEmpty || back.isEmpty) continue;
        if (front.length > maxFrontChars || back.length > maxBackChars) {
          warnings.add('第 ${batchIndex + 1} 批：丢弃超长卡片「${_cardSummary(front)}」');
          continue;
        }
        final rawHint = raw['hint']?.toString().trim();
        final hint = rawHint == null || rawHint.isEmpty
            ? null
            : (rawHint.length > maxHintChars
                  ? rawHint.substring(0, maxHintChars)
                  : rawHint);
        cards.add(
          GeneratedMemoryCard(
            front: front,
            back: back,
            hint: hint,
            sourceEntryId: sourceEntryId,
          ),
        );
      }
      return _ParsedCards(cards, warnings);
    } catch (_) {
      return _ParsedCards(const [], ['第 ${batchIndex + 1} 批：返回的 JSON 解析失败']);
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

  static String _cardSummary(String front) {
    final compact = front.replaceAll(RegExp(r'\s+'), ' ').trim();
    return compact.length <= 30 ? compact : '${compact.substring(0, 30)}…';
  }

  ModelConfig? _findModel(List<ModelConfig> models, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}

class _ParsedCards {
  const _ParsedCards(this.cards, this.warnings);

  final List<GeneratedMemoryCard> cards;
  final List<String> warnings;
}
