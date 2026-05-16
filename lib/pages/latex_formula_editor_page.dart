import 'package:flutter/material.dart';

import 'mathlive_formula_editor_page.dart';

class LatexFormulaEditorPage extends StatelessWidget {
  final String initialFormula;
  final bool preferBlock;
  final String title;
  final bool? supportsEmbeddedMathLiveOverride;

  const LatexFormulaEditorPage({
    super.key,
    required this.initialFormula,
    required this.preferBlock,
    required this.title,
    this.supportsEmbeddedMathLiveOverride,
  });

  @override
  Widget build(BuildContext context) {
    return MathLiveFormulaEditorPage(
      title: title,
      initialFormula: initialFormula,
      preferBlock: preferBlock,
      supportsEmbeddedMathLiveOverride: supportsEmbeddedMathLiveOverride,
    );
  }
}
