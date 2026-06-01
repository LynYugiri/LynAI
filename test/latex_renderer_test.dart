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
}
