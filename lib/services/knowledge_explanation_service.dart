import '../models/knowledge_entry.dart';
import '../models/knowledge_explanation.dart';
import '../models/model_config.dart';
import '../providers/knowledge_provider.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import 'api_service.dart';

final class KnowledgeExplanationRecord {
  const KnowledgeExplanationRecord({
    required this.entry,
    required this.explanation,
    required this.saved,
  });

  final KnowledgeEntry entry;
  final KnowledgeExplanation explanation;
  final bool saved;
}

/// Generates short knowledge explanations and persists them through the
/// existing [KnowledgeProvider] mutation API.
final class KnowledgeExplanationService {
  KnowledgeExplanationService({
    required ApiService api,
    required ModelConfigProvider modelConfigs,
    required SettingsProvider settings,
    required KnowledgeProvider knowledge,
  }) : _api = api,
       _modelConfigs = modelConfigs,
       _settings = settings,
       _knowledge = knowledge;

  final ApiService _api;
  final ModelConfigProvider _modelConfigs;
  final SettingsProvider _settings;
  final KnowledgeProvider _knowledge;

  KnowledgeExplanationRecord? findSaved({
    required String categoryId,
    required String text,
  }) {
    final title = text.trim();
    if (title.isEmpty) return null;
    final category = _knowledge.categoryById(categoryId);
    if (category == null ||
        !_knowledge.isExplanationCategoryEnabled(category)) {
      return null;
    }
    final entry = _matchingEntry(categoryId, title);
    if (entry == null || !entry.enabled) return null;
    for (final explanation in _knowledge.explanationsForEntry(entry.id)) {
      if (explanation.content.trim().isNotEmpty) {
        return KnowledgeExplanationRecord(
          entry: entry,
          explanation: explanation,
          saved: true,
        );
      }
    }
    return null;
  }

  Future<String> generate({
    required String text,
    String? categoryId,
    String context = '',
    String sourceTitle = '',
    String sourceUrl = '',
  }) async {
    final title = text.trim();
    if (title.isEmpty) throw ArgumentError.value(text, 'text', '不能为空');
    final category = categoryId == null
        ? null
        : _knowledge.categoryById(categoryId);
    if (categoryId != null &&
        (category == null ||
            !_knowledge.isExplanationCategoryEnabled(category))) {
      throw StateError('所选知识类别不存在或已停用');
    }
    final model = _selectModel(category?.modelConfigId);
    if (model == null) throw StateError('没有可用的聊天模型，请先配置模型');
    final categoryPrompt = category?.explanationPrompt.trim() ?? '';
    final response = await _api.sendChatRequest(model, [
      {
        'role': 'system',
        'content':
            '你是知识库释义助手。请准确、清晰地解释用户指定的概念或文本。'
            '直接输出适合保存到知识库的 Markdown 正文，不要复述任务，不要添加“释义”标题。'
            '必要时可使用列表、示例和 LaTeX；不确定的信息要明确说明，不要编造来源。'
            '${categoryPrompt.isEmpty ? '' : '\n\n类别专用要求：\n$categoryPrompt'}',
      },
      {
        'role': 'user',
        'content': buildRequestText(
          text: title,
          context: context,
          sourceTitle: sourceTitle,
          sourceUrl: sourceUrl,
        ),
      },
    ]);
    final content = response.content.trim();
    if (content.isEmpty) throw StateError('模型未返回释义内容');
    return content;
  }

  Future<KnowledgeExplanationRecord> save({
    required String categoryId,
    required String text,
    required String explanation,
    String context = '',
    String sourceTitle = '',
    String sourceUrl = '',
  }) async {
    final category = _knowledge.categoryById(categoryId);
    if (category == null ||
        !_knowledge.isExplanationCategoryEnabled(category)) {
      throw StateError('所选知识类别不存在或已停用');
    }
    final content = explanation.trim();
    if (content.isEmpty) throw ArgumentError('释义内容不能为空');
    final saved = await _knowledge.saveExplanationBundle(
      categoryId: category.id,
      title: text.trim(),
      entryContent: context.trim(),
      explanation: content,
      sourceTitle: sourceTitle.trim(),
      sourceUrl: sourceUrl.trim(),
    );
    return KnowledgeExplanationRecord(
      entry: saved.entry,
      explanation: saved.explanation,
      saved: true,
    );
  }

  ModelConfig? _selectModel(String? categoryModelId) {
    final models = _modelConfigs.enabledModelsByCategory(
      ModelConfig.categoryChat,
    );
    if (models.isEmpty) return null;
    final categoryModel = _findModel(models, categoryModelId);
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

  ModelConfig? _findModel(List<ModelConfig> models, String? id) {
    if (id == null || id.isEmpty) return null;
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  KnowledgeEntry? _matchingEntry(String categoryId, String title) {
    final normalized = _normalizeTitle(title);
    for (final entry in _knowledge.entriesForCategory(categoryId)) {
      if (_normalizeTitle(entry.title) == normalized) return entry;
    }
    return null;
  }

  static String buildRequestText({
    required String text,
    String context = '',
    String sourceTitle = '',
    String sourceUrl = '',
  }) {
    final output = StringBuffer('待解释文本：\n$text');
    if (context.trim().isNotEmpty) {
      output.write('\n\n上下文：\n${context.trim()}');
    }
    if (sourceTitle.trim().isNotEmpty) {
      output.write('\n\n来源标题：${sourceTitle.trim()}');
    }
    if (sourceUrl.trim().isNotEmpty) {
      output.write('\n来源链接：${sourceUrl.trim()}');
    }
    return output.toString();
  }

  static String _normalizeTitle(String value) => value.trim().toLowerCase();
}
