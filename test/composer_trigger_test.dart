import 'package:flutter_test/flutter_test.dart';

import 'package:lynai/services/composer_trigger.dart';

/// 在 [text] 末尾（或指定光标）检测触发。
ComposerTriggerMatch? detectAt(String text, [int? cursor]) =>
    detectComposerTrigger(text: text, cursor: cursor ?? text.length);

void main() {
  test('@ at the start of the text triggers a reference palette', () {
    final match = detectAt('@');
    expect(match, isNotNull);
    expect(match!.kind, ComposerTriggerKind.reference);
    expect(match.start, 0);
    expect(match.end, 1);
    expect(match.query, '');
    expect(match.symbol, '@');
    expect(match.isReference, isTrue);
  });

  test('@ after whitespace triggers and keeps the query', () {
    final match = detectAt('帮我看看 @项目');
    expect(match!.query, '项目');
    expect(match.start, '帮我看看 '.length);
  });

  test('space inside the token closes the trigger, text stays plain', () {
    expect(detectAt('@笔记 '), isNull);
    expect(detectAt('@笔记 你好'), isNull);
    // 光标停在空格之前仍是合法触发；越过空格才失效。
    expect(detectAt('@笔记 你好', 3)!.query, '笔记');
  });

  test('newline closes the trigger', () {
    expect(detectAt('@笔记\n'), isNull);
  });

  test('slash only triggers at the beginning of a line', () {
    final atStart = detectAt('/压');
    expect(atStart!.kind, ComposerTriggerKind.command);
    expect(atStart.query, '压');

    // 缩进后仍算行首，便于列表里对齐书写。
    expect(detectAt('  /压')!.query, '压');
    // 行中斜杠属于正文：URL、路径、A/B、和/或都不触发。
    expect(detectAt('https://example.com'), isNull);
    expect(detectAt('看 a/b 两种'), isNull);
    expect(detectAt('和/或'), isNull);
    // 换行后的行首重新生效。
    expect(detectAt('第一行\n/总结')!.query, '总结');
  });

  test('email and path forms never trigger', () {
    expect(detectAt('user@example.com'), isNull);
    expect(detectAt('看看 user@'), isNull);
  });

  test('collapsed selection beyond text or invalid cursor yields no trigger', () {
    expect(detectComposerTrigger(text: '@a', cursor: -1), isNull);
    expect(detectComposerTrigger(text: '@a', cursor: 99), isNull);
    expect(detectComposerTrigger(text: '@a', cursor: null), isNull);
  });

  test('cursor in the middle uses only the text before it', () {
    final match = detectAt('@笔记abc', 3);
    expect(match!.query, '笔记');
    expect(match.end, 3);
  });

  test('reference trigger works on a later line after a newline', () {
    final match = detectAt('第一行\n@');
    expect(match!.kind, ComposerTriggerKind.reference);
    expect(match.start, '第一行\n'.length);
  });
}
