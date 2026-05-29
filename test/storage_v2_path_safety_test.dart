import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test('StorageV2Service rejects note page paths that escape root', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_storage_path_test_',
    );
    try {
      final storage = StorageV2Service(rootDirectory: root);
      final page = StorageV2NotePage(
        id: 'p1',
        noteId: 'n1',
        title: 'bad',
        fileName: 'bad.md',
        relativePath: '../escape.md',
        sortOrder: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      );

      expect(
        () => storage.writeNotePage(page, 'owned'),
        throwsA(isA<ArgumentError>()),
      );
      expect(await File('${root.path}/escape.md').exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test(
    'StorageV2Service normalizes backslashes before safety checks',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_storage_backslash_test_',
      );
      try {
        final storage = StorageV2Service(rootDirectory: root);
        final page = StorageV2NotePage(
          id: 'p1',
          noteId: 'n1',
          title: 'bad',
          fileName: 'bad.md',
          relativePath: r'notes\n1\..\..\escape.md',
          sortOrder: 0,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
        );

        expect(() => storage.readNotePage(page), throwsA(isA<ArgumentError>()));
      } finally {
        await root.delete(recursive: true);
      }
    },
  );

  test('StorageV2Service rejects absolute resource relative paths', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_storage_resource_path_test_',
    );
    try {
      final storage = StorageV2Service(rootDirectory: root);
      const resource = StorageV2Resource(
        id: 'r1',
        kind: 'documents',
        role: 'message_attachment',
        originalPath: '/tmp/a.txt',
        originalName: 'a.txt',
        relativePath: '/tmp/escape.txt',
        mimeType: 'text/plain',
        size: 1,
        sha256Hash: null,
        missing: false,
      );

      expect(
        () => storage.resourceFile(resource),
        throwsA(isA<ArgumentError>()),
      );
    } finally {
      await root.delete(recursive: true);
    }
  });
}
