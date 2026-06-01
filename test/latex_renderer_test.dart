import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/widgets/latex_renderer.dart';

void main() {
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
    expect(MarkdownWithLatex.debugMermaidBody('```markdown\ncode\n```'), isNull);
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

  testWidgets('mermaid renders as code block when renderMermaid is false even with LaTeX in document', (
    WidgetTester tester,
  ) async {
    const content = '前文 \$x^2\$\n\n'
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
  });
}
