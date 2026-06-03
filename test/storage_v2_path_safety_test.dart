import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test('StorageV2Service rejects invalid storage manifests', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_storage_probe_test_',
    );
    try {
      final storageRoot = Directory('${root.path}/storage_v2');
      await storageRoot.create(recursive: true);
      await File(
        '${storageRoot.path}/manifest.json',
      ).writeAsString('{"type":"other.app","schemaVersion":2}', flush: true);
      await Directory('${storageRoot.path}/data').create();

      final storage = StorageV2Service(rootDirectory: root);
      final probe = await storage.probe();

      expect(probe.ready, isFalse);
      expect(probe.status, StorageV2ProbeStatus.invalidManifest);
      expect(await storage.exists(), isFalse);
    } finally {
      await root.delete(recursive: true);
    }
  });

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

  test('StorageV2Service resource snapshot removes stale rows', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_storage_resource_replace_test_',
    );
    try {
      final storage = StorageV2Service(rootDirectory: root);
      await storage.writeDataFile('resources.json', {
        'resources': [
          {
            'id': 'r1',
            'kind': 'documents',
            'role': 'message_attachment',
            'originalPath': '/tmp/a.txt',
            'originalName': 'a.txt',
            'relativePath': 'assets/documents/a.txt',
            'mimeType': 'text/plain',
            'size': 1,
            'missing': false,
          },
          {
            'id': 'r2',
            'kind': 'documents',
            'role': 'message_attachment',
            'originalPath': '/tmp/b.txt',
            'originalName': 'b.txt',
            'relativePath': 'assets/documents/b.txt',
            'mimeType': 'text/plain',
            'size': 2,
            'missing': false,
          },
        ],
      });
      await storage.writeDataFile('resources.json', {
        'resources': [
          {
            'id': 'r2',
            'kind': 'documents',
            'role': 'message_attachment',
            'originalPath': '/tmp/b.txt',
            'originalName': 'b.txt',
            'relativePath': 'assets/documents/b.txt',
            'mimeType': 'text/plain',
            'size': 2,
            'missing': false,
          },
        ],
      });

      final resources = await storage.loadResources();

      expect(resources.map((resource) => resource.id), ['r2']);
    } finally {
      await root.delete(recursive: true);
    }
  });

  test('StorageV2Service preserves concurrent resource imports', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_storage_resource_concurrent_test_',
    );
    final source = await Directory.systemTemp.createTemp(
      'lynai_storage_resource_source_test_',
    );
    try {
      final first = File('${source.path}/first.txt');
      final second = File('${source.path}/second.txt');
      await first.writeAsString('first', flush: true);
      await second.writeAsString('second', flush: true);

      final storage = StorageV2Service(rootDirectory: root);
      await Future.wait([
        storage.importResourceFile(
          first.path,
          originalName: 'first.txt',
          mimeType: 'text/plain',
          role: 'message_attachment',
        ),
        storage.importResourceFile(
          second.path,
          originalName: 'second.txt',
          mimeType: 'text/plain',
          role: 'message_attachment',
        ),
      ]);

      final resources = await storage.loadResources();

      expect(resources.map((resource) => resource.originalName).toSet(), {
        'first.txt',
        'second.txt',
      });
    } finally {
      await root.delete(recursive: true);
      await source.delete(recursive: true);
    }
  });

  test('StorageV2Database shared close keeps other handles usable', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_storage_db_shared_close_test_',
    );
    try {
      final storageRoot = Directory('${root.path}/storage_v2');
      final first = StorageV2Database(storageRoot);
      final second = StorageV2Database(storageRoot);
      await first.writeDataFile('resources.json', {'resources': []});
      await second.loadDataFile('resources.json');

      await first.close();
      await second.writeDataFile('resources.json', {
        'resources': [
          {
            'id': 'r1',
            'kind': 'documents',
            'role': 'message_attachment',
            'originalPath': '/tmp/a.txt',
            'originalName': 'a.txt',
            'relativePath': 'assets/documents/a.txt',
            'mimeType': 'text/plain',
            'size': 1,
            'missing': false,
          },
        ],
      });

      final data = await second.loadDataFile('resources.json');
      expect(data!['resources'], hasLength(1));
      await second.close();
    } finally {
      await root.delete(recursive: true);
    }
  });
}
