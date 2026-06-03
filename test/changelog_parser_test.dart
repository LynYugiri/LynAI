import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/utils/changelog_parser.dart';

void main() {
  test('ChangelogParser strips build and prerelease version suffixes', () {
    final parser = ChangelogParser();

    expect(parser.versionCandidatesForTest('2.3.2+12'), ['2.3.2+12', '2.3.2']);
    expect(parser.versionCandidatesForTest('2.3.2-beta'), [
      '2.3.2-beta',
      '2.3.2',
    ]);
    expect(parser.versionCandidatesForTest('2.3.2'), ['2.3.2']);
  });

  test('ChangelogParser parses markdown changelog entries', () {
    final parser = ChangelogParser();
    final entry = parser.parseForTest('''
## v2.3.2 - 2026-06-03

### 修复
- 修复更新日志展示
''', 'changelogs/v2.3.2.md');

    expect(entry, isNotNull);
    expect(entry!.version, '2.3.2');
    expect(entry.date, '2026-06-03');
    expect(entry.sections.single.title, '修复');
    expect(entry.sections.single.items.single, '修复更新日志展示');
  });
}
