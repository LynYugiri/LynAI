import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/services/composer_command_registry.dart';

void main() {
  test('built-in commands are Chinese-first with English aliases', () {
    final registry = buildBuiltInCommandRegistry();
    final names = registry.commands.map((command) => command.name).toList();
    expect(names, ['压缩', '总结']);
    expect(
      registry.commands.first.aliases,
      contains('compact'),
    );
    expect(
      registry.commands.last.aliases,
      contains('summarize'),
    );
    expect(
      registry.commands.map((command) => command.kind),
      everyElement(ComposerCommandKind.run),
    );
  });

  test('name and alias prefix hit before title or description matches', () {
    final registry = buildBuiltInCommandRegistry();
    // 「压」同时命中「压缩」的名称与「总结」说明里的「压缩」，按得分排序。
    expect(registry.search('压').first.name, '压缩');
    expect(registry.search('压缩').first.name, '压缩');
    // 名称/别名命中排在说明子串命中之前，因此 compact 的第一条是「压缩」。
    expect(registry.search('compact').first.name, '压缩');
    expect(registry.search('summ').first.name, '总结');
    // 标题/说明命中仍然可用。
    expect(
      registry.search('上下文').map((command) => command.name),
      contains('压缩'),
    );
  });

  test('unmatched query returns an empty list so text stays plain', () {
    final registry = buildBuiltInCommandRegistry();
    expect(registry.search('没这条命令'), isEmpty);
    expect(registry.search('zip'), isEmpty);
  });

  test('empty query lists every command', () {
    final registry = buildBuiltInCommandRegistry();
    expect(registry.search(''), hasLength(2));
  });

  test('plugin commands can be appended and searched by the same rules', () {
    final registry = buildBuiltInCommandRegistry(
      extra: const [
        ComposerCommand(
          name: '翻译',
          aliases: ['translate'],
          title: '翻译选中内容',
          kind: ComposerCommandKind.insert,
          insertText: '把下面内容翻译成中文：',
        ),
      ],
    );
    final match = registry.search('翻译').single;
    expect(match.kind, ComposerCommandKind.insert);
    expect(match.insertText, '把下面内容翻译成中文：');
    expect(match.actionId, isEmpty);
  });
}
