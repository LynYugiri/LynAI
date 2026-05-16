import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/pages/latex_formula_editor_page.dart';

void main() {
  Future<void> pumpEditor(WidgetTester tester, {String formula = ''}) {
    return tester.pumpWidget(
      MaterialApp(
        home: LatexFormulaEditorPage(
          initialFormula: formula,
          preferBlock: false,
          title: '编辑公式',
          supportsEmbeddedMathLiveOverride: false,
        ),
      ),
    );
  }

  testWidgets('unsupported platform falls back to source mode', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester, formula: r'E = mc^2');

    expect(find.textContaining('当前平台暂不支持内嵌 MathLive'), findsOneWidget);
    expect(find.text('源码模式'), findsOneWidget);
    expect(find.text('LaTeX 源码'), findsOneWidget);
  });

  testWidgets('example chips remain available in source fallback', (
    WidgetTester tester,
  ) async {
    await pumpEditor(tester);

    expect(find.text('m'), findsOneWidget);
    expect(find.textContaining(r'\frac{x}{y}'), findsWidgets);
  });
}
