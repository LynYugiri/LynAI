import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/workspace_file_service.dart';

void main() {
  late Directory root;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_workspace_file_');
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('list, read and atomic write inside mounted directory', () async {
    final service = const WorkspaceFileService();
    final nested = Directory('${root.path}/nested')
      ..createSync(recursive: true);
    File('${nested.path}/a.txt').writeAsStringSync('hello');
    File('${root.path}/b.txt').writeAsStringSync('world');

    final entries = await service.listDirectory(root.path, '');
    expect(
      entries.map((entry) => entry.name),
      containsAll(['nested', 'b.txt']),
    );
    expect(
      entries.firstWhere((entry) => entry.name == 'nested').isDirectory,
      isTrue,
    );

    expect(await service.readTextFile(root.path, 'nested/a.txt'), 'hello');
    await service.writeTextFile(root.path, 'nested/a.txt', 'updated');
    expect(await service.readTextFile(root.path, 'nested/a.txt'), 'updated');
  });

  test('rejects path traversal and binary files', () async {
    final service = const WorkspaceFileService();
    expect(WorkspaceFileService.normalizeRelative('../secret'), isNull);
    expect(WorkspaceFileService.normalizeRelative('/etc/passwd'), isNull);
    expect(
      () => service.readTextFile(root.path, '../secret'),
      throwsA(isA<FileSystemException>()),
    );

    final binary = File('${root.path}/bin.dat')..writeAsBytesSync([0, 1, 2, 3]);
    expect(
      () => service.readTextFile(root.path, 'bin.dat'),
      throwsA(isA<FileSystemException>()),
    );
    expect(binary.existsSync(), isTrue);
  });
}
