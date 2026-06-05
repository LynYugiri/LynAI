import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/tree_sitter_language_registry.dart';

void main() {
  test('TreeSitterLanguageRegistry resolves mainstream aliases', () {
    expect(TreeSitterLanguageRegistry.find('js')?.id, 'javascript');
    expect(TreeSitterLanguageRegistry.find('tsx')?.symbol, 'tree_sitter_tsx');
    expect(TreeSitterLanguageRegistry.find('py')?.id, 'python');
    expect(TreeSitterLanguageRegistry.find('c++')?.id, 'cpp');
    expect(TreeSitterLanguageRegistry.find('ps1')?.id, 'powershell');
    expect(TreeSitterLanguageRegistry.find('yml')?.id, 'yaml');
  });

  test('TreeSitterLanguageRegistry leaves unknown languages unsupported', () {
    expect(TreeSitterLanguageRegistry.find('not-a-real-language'), isNull);
    expect(TreeSitterLanguageRegistry.find(null), isNull);
  });
}
