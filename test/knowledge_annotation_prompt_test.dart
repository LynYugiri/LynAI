import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/knowledge_annotation_prompt.dart';

void main() {
  test('formatter includes enabled category aliases and rules', () {
    final snapshot = KnowledgeAnnotationPromptSnapshot(
      fallbackCategory: 'proper_noun',
      categories: [
        KnowledgeAnnotationCategorySnapshot(
          category: 'person',
          aliases: const ['人物', '角色'],
          rule: '仅标注有明确身份的人名',
        ),
        KnowledgeAnnotationCategorySnapshot(
          category: 'disabled',
          enabled: false,
          aliases: const ['隐藏'],
          rule: '不得出现',
        ),
      ],
    );

    final prompt = const KnowledgeAnnotationPromptFormatter().format(snapshot);
    expect(prompt, contains('[[category:text]]'));
    expect(prompt, contains('左侧 category'));
    expect(prompt, contains('右侧 text'));
    expect(prompt, contains('正确示例：[[person:张三]]'));
    expect(prompt, contains('错误示例：[[张三|person]]'));
    expect(prompt, contains('禁止使用 |'));
    expect(prompt, contains('fenced code、行内代码、URL 或 Markdown 链接'));
    expect(prompt, contains('回退类别：proper_noun'));
    expect(prompt, contains('- person；别名：人物、角色；应标注文本：仅标注有明确身份的人名'));
    expect(prompt, isNot(contains('disabled')));
    expect(prompt, isNot(contains('隐藏')));
  });

  test('formatter returns empty text without enabled categories', () {
    final snapshot = KnowledgeAnnotationPromptSnapshot(
      fallbackCategory: 'proper_noun',
      categories: [
        KnowledgeAnnotationCategorySnapshot(category: 'person', enabled: false),
      ],
    );

    expect(
      const KnowledgeAnnotationPromptFormatter().format(snapshot),
      isEmpty,
    );
  });
}
