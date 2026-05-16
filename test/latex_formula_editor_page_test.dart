import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/pages/latex_formula_editor_page.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester, String formula) {
    return tester.pumpWidget(
      MaterialApp(
        home: LatexFormulaEditorPage(
          initialFormula: formula,
          preferBlock: false,
          title: '编辑公式',
        ),
      ),
    );
  }

  testWidgets('plain x^2 imports into visual editor', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester, r'x^2');

    expect(find.textContaining('暂不支持的结构'), findsNothing);
    expect(find.text('LaTeX 源码'), findsNothing);
  });

  testWidgets('single variable imports into visual editor', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester, 'm');

    expect(find.textContaining('暂不支持的结构'), findsNothing);
    expect(find.text('LaTeX 源码'), findsNothing);
  });

  testWidgets('plain mc^2 imports into visual editor', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester, r'mc^2');

    expect(find.textContaining('暂不支持的结构'), findsNothing);
    expect(find.text('LaTeX 源码'), findsNothing);
  });

  testWidgets('equation with equals falls back to source mode', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester, r'E = mc^2');

    expect(find.textContaining('暂不支持的结构'), findsOneWidget);
    expect(find.text('LaTeX 源码'), findsOneWidget);
  });
}
