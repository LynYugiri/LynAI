import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_markdown_plus/flutter_markdown_plus.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/widgets/latex_renderer.dart';

void main() {
  testWidgets('MarkdownWithLatex forwards markdown link taps', (
    WidgetTester tester,
  ) async {
    String? href;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(
            content: '打开 [LynAI](https://example.com) 或 https://dart.dev',
            onTapLink: (_, value, _) => href = value,
          ),
        ),
      ),
    );

    final richText = tester
        .widgetList<RichText>(find.byType(RichText))
        .firstWhere((widget) => widget.text.toPlainText().contains('LynAI'));
    final links = <TapGestureRecognizer>[];
    bool collect(InlineSpan span) {
      if (span is TextSpan) {
        if (span.recognizer case final TapGestureRecognizer recognizer) {
          links.add(recognizer);
        }
      }
      return true;
    }

    richText.text.visitChildren(collect);
    links.first.onTap!();
    expect(href, 'https://example.com');
    links.last.onTap!();
    expect(href, 'https://dart.dev');
  });

  testWidgets('MarkdownWithLatex keeps the default selection menu', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownWithLatex(content: '可选择文本')),
      ),
    );

    expect(
      tester
          .widget<SelectionArea>(find.byType(SelectionArea))
          .contextMenuBuilder,
      isNotNull,
    );
  });

  testWidgets('MarkdownWithLatex renders parenthesized inline latex', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownWithLatex(content: r'演示 \(x^2 + 1\) 公式')),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining(r'\(x^2 + 1\)'), findsNothing);
  });

  testWidgets(
    'knowledge annotation resolves alias and reports final category',
    (WidgetTester tester) async {
      KnowledgeAnnotationRenderData? tapped;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: MarkdownWithLatex(
              content: '认识 [[person:张三]]',
              knowledgeCategoryResolver: (value) =>
                  value == 'person' ? 'people' : null,
              onTapKnowledgeAnnotation: (value) => tapped = value,
            ),
          ),
        ),
      );

      expect(find.text('张三'), findsOneWidget);
      expect(find.textContaining('[[person:张三]]'), findsNothing);
      await tester.tap(find.text('张三'));
      expect(tapped?.sourceCategory, 'person');
      expect(tapped?.category, 'people');
      expect(tapped?.text, '张三');
    },
  );

  testWidgets('unknown annotation resolves the fallback category alias', (
    WidgetTester tester,
  ) async {
    KnowledgeAnnotationRenderData? tapped;
    final resolved = <String>[];
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(
            content: '[[unknown:条目]]',
            fallbackKnowledgeCategory: 'general-alias',
            knowledgeCategoryResolver: (value) {
              resolved.add(value);
              return value == 'general-alias' ? 'general' : null;
            },
            onTapKnowledgeAnnotation: (value) => tapped = value,
          ),
        ),
      ),
    );

    await tester.tap(find.text('条目'));
    expect(resolved, ['unknown', 'general-alias']);
    expect(tapped?.category, 'general');
  });

  testWidgets('knowledge annotation uses the final category color', (
    WidgetTester tester,
  ) async {
    const categoryColor = Color(0xFF7C3AED);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(
            content: '[[person:张三]]',
            knowledgeCategoryResolver: (value) => 'person-id',
            knowledgeCategoryColorResolver: (value) =>
                value == 'person-id' ? categoryColor : null,
          ),
        ),
      ),
    );

    final text = tester.widget<Text>(find.text('张三'));
    expect(text.style?.color, categoryColor);
    expect(text.style?.decorationStyle, TextDecorationStyle.dotted);
    final decoration =
        tester
                .widget<DecoratedBox>(
                  find
                      .ancestor(
                        of: find.text('张三'),
                        matching: find.byType(DecoratedBox),
                      )
                      .first,
                )
                .decoration
            as BoxDecoration;
    expect(decoration.color, categoryColor.withValues(alpha: 0.1));
  });

  testWidgets('knowledge annotations ignore code and keep streaming source', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(
            content:
                '`[[person:inline]]`\n\n```text\n[[person:block]]\n```\n\n[[person:unfinished',
          ),
        ),
      ),
    );

    expect(find.textContaining('[[person:inline]]'), findsWidgets);
    expect(find.textContaining('[[person:block]]'), findsWidgets);
    expect(find.textContaining('[[person:unfinished'), findsWidgets);
    expect(find.text('inline'), findsNothing);
    expect(find.text('block'), findsNothing);
  });

  testWidgets('pipe annotation variants remain literal text', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(
            content: '[[张三|person]] [[person|张三]] [[person:张三|李四]]',
          ),
        ),
      ),
    );

    expect(find.textContaining('[[张三|person]]'), findsWidgets);
    expect(find.textContaining('[[person|张三]]'), findsWidgets);
    expect(find.textContaining('[[person:张三|李四]]'), findsWidgets);
    expect(find.text('张三'), findsNothing);
  });

  testWidgets('zero knowledge category color falls back to theme primary', (
    WidgetTester tester,
  ) async {
    const primary = Color(0xFF2468AC);
    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: primary)),
        home: Scaffold(
          body: MarkdownWithLatex(
            content: '[[person:张三]]',
            knowledgeCategoryResolver: (_) => 'person-id',
            knowledgeCategoryColorResolver: (_) => null,
          ),
        ),
      ),
    );

    final context = tester.element(find.text('张三'));
    expect(
      tester.widget<Text>(find.text('张三')).style?.color,
      Theme.of(context).colorScheme.primary,
    );
  });

  testWidgets('MarkdownWithLatex edit callback keeps block source range', (
    WidgetTester tester,
  ) async {
    String? capturedSource;
    int? capturedStart;
    int? capturedEnd;
    const blockSource =
        r'$$'
        '\n'
        'x+1'
        '\n'
        r'$$';
    const content = '前文\n$blockSource\n后文';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(
            content: content,
            onEditLatexBlock: (source, start, end) {
              capturedSource = source;
              capturedStart = start;
              capturedEnd = end;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('编辑'));

    expect(capturedSource, blockSource);
    expect(capturedStart, content.indexOf(blockSource));
    expect(capturedEnd, capturedStart! + capturedSource!.length);
  });

  testWidgets('LaTeX edit callback offset correct after fenced code block', (
    WidgetTester tester,
  ) async {
    String? capturedSource;
    int? capturedStart;
    int? capturedEnd;
    const before = 'text\n';
    const fenced = '```dart\nvoid main() {}\n```';
    const latexSource = '\$\$\nx+1\n\$\$';
    final content = '$before$fenced\n\n$latexSource';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(
            content: content,
            onEditLatexBlock: (source, start, end) {
              capturedSource = source;
              capturedStart = start;
              capturedEnd = end;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('编辑'));

    expect(capturedSource, latexSource);
    expect(capturedStart, content.indexOf(latexSource));
    expect(capturedEnd, capturedStart! + capturedSource!.length);
  });

  testWidgets('MarkdownWithLatex ignores invalid fenced code language', (
    WidgetTester tester,
  ) async {
    const content = '```=\n=\n```';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownWithLatex(content: content)),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('='), findsWidgets);
  });

  testWidgets('MarkdownWithLatex can leave Mermaid as code when disabled', (
    WidgetTester tester,
  ) async {
    const content = '''```mermaid
mindmap
  root((LynAI))
```''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(content: content, renderMermaid: false),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('mindmap'), findsWidgets);
    expect(find.textContaining('root((LynAI))'), findsWidgets);
  });

  testWidgets('MarkdownWithLatex code edit callback keeps fence range', (
    WidgetTester tester,
  ) async {
    String? capturedSource;
    int? capturedStart;
    int? capturedEnd;
    const fence = '```dart title="main"\nvoid main() {}\n```';
    const content = '前文\n$fence\n后文';

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(
            content: content,
            onEditCodeBlock: (source, start, end) {
              capturedSource = source;
              capturedStart = start;
              capturedEnd = end;
            },
          ),
        ),
      ),
    );

    await tester.tap(find.byTooltip('编辑'));

    expect(capturedSource, fence);
    expect(capturedStart, content.indexOf(fence));
    expect(capturedEnd, capturedStart! + capturedSource!.length);
  });

  testWidgets('MarkdownWithLatex renders latex fenced block as formula', (
    WidgetTester tester,
  ) async {
    const content = '''```latex
x^2 + 1
```''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(body: MarkdownWithLatex(content: content)),
      ),
    );

    expect(find.byType(Math), findsOneWidget);
    expect(find.textContaining('```latex'), findsNothing);
  });

  testWidgets('mermaid fence extraction excludes closing fence', (
    WidgetTester tester,
  ) async {
    const content = '''```mermaid
graph TD
    A --> B
```
后文''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(content: content, renderMermaid: false),
        ),
      ),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.textContaining('graph TD'), findsOneWidget);
    expect(find.textContaining('A --> B'), findsOneWidget);
    expect(find.textContaining('后文'), findsOneWidget);
  });

  // --- debugSegments offset tests ---

  test('debugSegments tracks correct offsets for non-fenced + fenced', () {
    const content = '前文\n```python\ncode\n```';
    final segments = MarkdownWithLatex.debugSegments(content);

    expect(segments.length, 2);
    expect(segments[0]['isFencedCodeBlock'], false);
    expect(segments[0]['text'], '前文\n');
    expect(segments[0]['startOffset'], 0);

    expect(segments[1]['isFencedCodeBlock'], true);
    expect(segments[1]['text'], '```python\ncode\n```');
    expect(segments[1]['startOffset'], 3);
  });

  test('debugSegments tracks offset when fence at start of content', () {
    const content = '```mermaid\ngraph TD\n```';
    final segments = MarkdownWithLatex.debugSegments(content);

    expect(segments.length, 1);
    expect(segments[0]['isFencedCodeBlock'], true);
    expect(segments[0]['startOffset'], 0);
  });

  test('debugSegments tracks offset with multiple alternating segments', () {
    const content = 'a\n```x\nb\n```\n\nc\n```y\nd\n```\n\ne';
    final segments = MarkdownWithLatex.debugSegments(content);

    expect(segments.length, 5);
    expect(segments[0]['isFencedCodeBlock'], false);
    expect(segments[0]['startOffset'], 0);

    expect(segments[1]['isFencedCodeBlock'], true);
    expect(segments[1]['startOffset'], 2); // after "a\n"

    expect(segments[2]['isFencedCodeBlock'], false);
    expect(segments[2]['startOffset'], 13); // after first fence

    expect(segments[3]['isFencedCodeBlock'], true);
    expect(segments[3]['startOffset'], 16); // after "\nc\n"

    expect(segments[4]['isFencedCodeBlock'], false);
    expect(segments[4]['startOffset'], 27); // after second fence
  });

  test('debugSegments handles tilde fences', () {
    const content = '前\n~~~mermaid\ngraph\n~~~\n后';
    final segments = MarkdownWithLatex.debugSegments(content);

    expect(segments.length, 3);
    expect(segments[0]['isFencedCodeBlock'], false);
    expect(segments[0]['startOffset'], 0);

    expect(segments[1]['isFencedCodeBlock'], true);
    expect(segments[1]['startOffset'], 2); // after "前\n"

    expect(segments[2]['isFencedCodeBlock'], false);
    expect(segments[2]['startOffset'], 23); // after tilde fence
  });

  test('debugSegments handles indented fences', () {
    const content = '   ```mermaid\n   graph\n   ```';
    final segments = MarkdownWithLatex.debugSegments(content);

    expect(segments.length, 1);
    expect(segments[0]['isFencedCodeBlock'], true);
    expect(segments[0]['startOffset'], 0);
  });

  test('debugSegments stays consistent for empty content', () {
    final segments = MarkdownWithLatex.debugSegments('');
    expect(segments, isEmpty);
  });

  test('MarkdownCodeFence parses language info and body offsets', () {
    const source = '```dart title="main"\nvoid main() {}\n```';
    final fence = MarkdownCodeFence.tryParse(source, startOffset: 8);

    expect(fence, isNotNull);
    expect(fence!.language, 'dart');
    expect(fence.info, 'dart title="main"');
    expect(fence.body, 'void main() {}');
    expect(fence.bodyStart, 8 + '```dart title="main"\n'.length);
    expect(fence.bodyEnd, fence.bodyStart + 'void main() {}'.length);
    expect(fence.wrapBody('print(1);'), '```dart title="main"\nprint(1);\n```');
  });

  test('MarkdownCodeFence parses tilde fences', () {
    const source = '~~~python\nprint(1)\n~~~';
    final fence = MarkdownCodeFence.tryParse(source);

    expect(fence, isNotNull);
    expect(fence!.language, 'python');
    expect(fence.bodyForDisplay, 'print(1)');
    expect(fence.wrapBody('print(2)\n'), '~~~python\nprint(2)\n~~~');
  });

  test('MarkdownCodeFence preserves unclosed fences when edited', () {
    const source = '```js\nconsole.log(1)';
    final fence = MarkdownCodeFence.tryParse(source);

    expect(fence, isNotNull);
    expect(fence!.hasClosingFence, false);
    expect(fence.bodyForDisplay, 'console.log(1)');
    expect(fence.wrapBody('console.log(2)'), '```js\nconsole.log(2)');
  });

  // --- debugMermaidBody tests ---

  test('debugMermaidBody detects mermaid language', () {
    const fence = '```mermaid\ngraph TD\n    A --> B\n```';
    final body = MarkdownWithLatex.debugMermaidBody(fence);
    expect(body, 'graph TD\n    A --> B');
  });

  test('debugMermaidBody detects mmd alias', () {
    const fence = '```mmd\nflowchart LR\n    A --> B\n```';
    final body = MarkdownWithLatex.debugMermaidBody(fence);
    expect(body, 'flowchart LR\n    A --> B');
  });

  test('debugMermaidBody returns null for non-mermaid language', () {
    expect(MarkdownWithLatex.debugMermaidBody('```python\ncode\n```'), isNull);
    expect(MarkdownWithLatex.debugMermaidBody('```\ncode\n```'), isNull);
    expect(
      MarkdownWithLatex.debugMermaidBody('```markdown\ncode\n```'),
      isNull,
    );
  });

  test('debugMermaidBody returns null for empty body', () {
    expect(MarkdownWithLatex.debugMermaidBody('```mermaid\n```'), isNull);
    expect(MarkdownWithLatex.debugMermaidBody('```mermaid\n\n```'), isNull);
  });

  test('debugMermaidBody returns null for insufficient lines', () {
    expect(MarkdownWithLatex.debugMermaidBody('```mermaid'), isNull);
    expect(MarkdownWithLatex.debugMermaidBody('```mermaid\n'), isNull);
  });

  test('debugMermaidBody strips trailing blank lines before closing fence', () {
    const fence = '```mermaid\ngraph TD\n\n\n```';
    final body = MarkdownWithLatex.debugMermaidBody(fence);
    expect(body, 'graph TD');
  });

  test('debugMermaidBody handles indented opening fence', () {
    const fence = '  ```mermaid\ngraph TD\n  ```';
    final body = MarkdownWithLatex.debugMermaidBody(fence);
    expect(body, 'graph TD');
  });

  test('debugMermaidBody ignores extraneous info string trailing content', () {
    const fence = '```mermaid {.class}\ngraph TD\n```';
    final body = MarkdownWithLatex.debugMermaidBody(fence);
    expect(body, 'graph TD');
  });

  // --- mermaid vs markdown isolation tests ---

  testWidgets('mermaid disabled falls back to code block not raw text', (
    WidgetTester tester,
  ) async {
    const content = '''```mermaid
graph LR
    A --> B
```''';

    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(content: content, renderMermaid: false),
        ),
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('graph LR'), findsOneWidget);
    expect(find.textContaining('A --> B'), findsOneWidget);
  });

  testWidgets(
    'mermaid renders as code block when renderMermaid is false even with LaTeX in document',
    (WidgetTester tester) async {
      const content =
          '前文 \$x^2\$\n\n'
          '```mermaid\n'
          'graph TD\n'
          '    A --> B\n'
          '```';

      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: MarkdownWithLatex(content: content, renderMermaid: false),
          ),
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.textContaining('graph TD'), findsOneWidget);
      expect(find.textContaining('A --> B'), findsOneWidget);
    },
  );

  group('MarkdownWithLatex 表格', () {
    const wideTable = '''
| 名称 | 类型 | 默认值 | 说明 | 备注 |
| --- | --- | --- | --- | --- |
| maxToolRounds | int | 24 | 单次 run 的工具轮数上限 | 共享默认值 |
| contextWindow | int | 128000 | 上下文窗口 | 可本地覆盖 |
''';
    const narrowTable = '''
| 项 | 值 |
| --- | --- |
| 模式 | 快速 |
| 轮数 | 24 |
''';
    final longCellTable =
        '| 项 | 说明 |\n'
        '| --- | --- |\n'
        '| relay | '
        '${List.filled(6, '这是一段用来测试超长单元格换行的说明文字。').join()}'
        ' |\n';

    Finder horizontalScroller() => find.byWidgetPredicate(
      (widget) =>
          widget is SingleChildScrollView &&
          widget.scrollDirection == Axis.horizontal,
    );

    Future<void> pumpTable(
      WidgetTester tester,
      String content, {
      bool wrapTables = false,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: SizedBox(
                width: 360,
                child: MarkdownWithLatex(
                  content: content,
                  selectable: false,
                  wrapTables: wrapTables,
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('宽表格按内容排布并横向滚动', (WidgetTester tester) async {
      await pumpTable(tester, wideTable);

      expect(tester.takeException(), isNull);
      expect(horizontalScroller(), findsOneWidget);
      expect(tester.getSize(find.byType(Table)).width, greaterThan(360));
      // 长标识符所在列比短标签列宽，说明列宽来自内容而不是平分容器。
      final firstColumn = tester.getSize(find.byType(TableCell).at(0)).width;
      final secondColumn = tester.getSize(find.byType(TableCell).at(1)).width;
      expect(firstColumn, greaterThan(secondColumn));
    });

    testWidgets('窄表格贴合容器宽度', (WidgetTester tester) async {
      await pumpTable(tester, narrowTable);

      expect(tester.takeException(), isNull);
      expect(tester.getSize(find.byType(Table)).width, lessThanOrEqualTo(360));
    });

    testWidgets('超长单元格在上限内换行', (WidgetTester tester) async {
      await pumpTable(tester, longCellTable);

      expect(tester.takeException(), isNull);
      final cells = find.byType(TableCell);
      expect(cells, findsWidgets);
      for (var i = 0; i < cells.evaluate().length; i++) {
        expect(tester.getSize(cells.at(i)).width, lessThanOrEqualTo(202));
      }
      // 说明列换行后行高明显超过单行（第 0、1 个单元格是表头，第 3 个是长单元格）。
      expect(tester.getSize(cells.at(3)).height, greaterThan(60));
      expect(tester.getSize(find.byType(Table)).width, lessThanOrEqualTo(360));
    });

    testWidgets('wrapTables 关闭横向滚动', (WidgetTester tester) async {
      await pumpTable(tester, wideTable, wrapTables: true);

      expect(tester.takeException(), isNull);
      expect(horizontalScroller(), findsNothing);
      expect(tester.getSize(find.byType(Table)).width, lessThanOrEqualTo(360));
    });

    testWidgets('重复 build 得到相等的样式表', (WidgetTester tester) async {
      Widget build() => const MaterialApp(
        home: Scaffold(
          body: MarkdownWithLatex(content: wideTable, selectable: false),
        ),
      );

      await tester.pumpWidget(build());
      final first = tester
          .widget<MarkdownBody>(find.byType(MarkdownBody))
          .styleSheet;
      await tester.pumpWidget(build());
      final second = tester
          .widget<MarkdownBody>(find.byType(MarkdownBody))
          .styleSheet;
      // 样式表不相等会让 MarkdownBody 重新解析整段内容，流式渲染会退化。
      expect(second, first);
    });
  });
}
