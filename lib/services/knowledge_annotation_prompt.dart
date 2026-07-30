/// Immutable prompt data for one knowledge annotation category.
class KnowledgeAnnotationCategorySnapshot {
  final String category;
  final bool enabled;
  final List<String> aliases;
  final String rule;

  KnowledgeAnnotationCategorySnapshot({
    required this.category,
    this.enabled = true,
    Iterable<String> aliases = const [],
    this.rule = '',
  }) : aliases = List.unmodifiable(
         aliases
             .map((alias) => alias.trim())
             .where((alias) => alias.isNotEmpty),
       );
}

/// Data-only snapshot consumed by [KnowledgeAnnotationPromptFormatter].
class KnowledgeAnnotationPromptSnapshot {
  final String fallbackCategory;
  final List<KnowledgeAnnotationCategorySnapshot> categories;

  KnowledgeAnnotationPromptSnapshot({
    required this.fallbackCategory,
    Iterable<KnowledgeAnnotationCategorySnapshot> categories = const [],
  }) : categories = List.unmodifiable(categories);
}

/// Formats knowledge annotation instructions without depending on providers or
/// persistence models.
class KnowledgeAnnotationPromptFormatter {
  const KnowledgeAnnotationPromptFormatter();

  String format(KnowledgeAnnotationPromptSnapshot snapshot) {
    final categories = snapshot.categories
        .where(
          (category) => category.enabled && category.category.trim().isNotEmpty,
        )
        .toList(growable: false);
    if (categories.isEmpty) return '';

    final output = StringBuffer()
      ..writeln('需要标注知识实体时，只能使用 [[category:text]]。')
      ..writeln('左侧 category 是下方列出的类别 alias，右侧 text 是原文中需要标注的文本。')
      ..writeln('正确示例：[[person:张三]]。')
      ..writeln('错误示例：[[张三|person]]、[[person|张三]]、[[张三:person]]。')
      ..writeln('标注中禁止使用 |；管道符及包含管道符的原文必须保持原样显示。')
      ..writeln('不要标注 fenced code、行内代码、URL 或 Markdown 链接的显示文字和目标地址，也不要改写它们。')
      ..writeln('只标注符合各类别“应标注文本”说明的原文；说明不定义格式、左右顺序或其他语法。');
    final fallbackCategory = snapshot.fallbackCategory.trim();
    if (fallbackCategory.isNotEmpty) {
      output.writeln('未知类别使用回退类别：$fallbackCategory。');
    }
    output.writeln('可用类别：');
    for (final category in categories) {
      final name = category.category.trim();
      final aliases = category.aliases.isEmpty
          ? ''
          : '；别名：${category.aliases.join('、')}';
      final rule = category.rule.trim().isEmpty
          ? ''
          : '；应标注文本：${category.rule.trim()}';
      output.writeln('- $name$aliases$rule');
    }
    return output.toString().trimRight();
  }
}
