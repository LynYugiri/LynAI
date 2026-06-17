import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

import 'storage_v2_service.dart';

/// Ensures the current `storage_v2` directory is ready for the app runtime.
///
/// Creates a fresh storage_v2 directory or upgrades an existing storage_v2
/// layout in place.
class StorageV2UpgradeService {
  StorageV2UpgradeService({StorageV2Service? storageV2})
    : _storageV2 = storageV2 ?? StorageV2Service();

  final StorageV2Service _storageV2;

  Future<void> ensureReady() async {
    final root = await _storageV2.storageRoot();
    if (!await root.exists()) await root.create(recursive: true);

    final manifestFile = File('${root.path}/manifest.json');
    if (!await manifestFile.exists()) {
      await _writeManifest(root);
      await _storageV2.loadDataFile('resources.json');
      return;
    }

    final manifest = await _readManifest(manifestFile);
    final type = manifest['type'];
    if (type != 'lynai.storage_v2') {
      throw const FormatException('storage_v2 manifest type is invalid');
    }
    final version = (manifest['schemaVersion'] as num?)?.toInt() ?? 1;
    if (version > StorageV2Service.currentLayoutVersion) {
      throw const FormatException('storage_v2 version is newer than this app');
    }
    if (version == StorageV2Service.currentLayoutVersion) {
      await _storageV2.loadDataFile('resources.json');
      return;
    }

    final backup = Directory(
      '${root.path}_backup_${DateTime.now().microsecondsSinceEpoch}',
    );
    await _copyDirectory(root, backup);
    try {
      await _upgradeResourcesToBlobs(root);
      await _writeManifest(root);
    } catch (_) {
      await _restoreBackup(root, backup);
      rethrow;
    }
  }

  Future<Map<String, dynamic>> _readManifest(File file) async {
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      throw const FormatException('storage_v2 manifest is not an object');
    }
    return Map<String, dynamic>.from(decoded);
  }

  Future<void> _writeManifest(Directory root) async {
    final manifest = {
      'type': 'lynai.storage_v2',
      'schemaVersion': StorageV2Service.currentLayoutVersion,
      'createdAt': DateTime.now().toUtc().toIso8601String(),
      'layout': {
        'database': 'app.db',
        'notes': 'notes/{noteId}/{pageFile}.md',
        'assets': 'assets/blobs/{sha256Prefix}/{sha256}',
      },
    };
    await File('${root.path}/manifest.json').writeAsString(
      const JsonEncoder.withIndent('  ').convert(manifest),
      flush: true,
    );
  }

  Future<void> _upgradeResourcesToBlobs(Directory root) async {
    final resources = await _storageV2.loadResources();
    var changed = false;
    final upgraded = <StorageV2Resource>[];
    for (final resource in resources) {
      final relativePath = resource.relativePath;
      if (relativePath == null || resource.missing) {
        upgraded.add(resource);
        continue;
      }
      if (_isBlobPath(relativePath)) {
        upgraded.add(resource);
        continue;
      }
      final source = File('${root.path}/$relativePath');
      if (!await source.exists()) {
        upgraded.add(
          StorageV2Resource(
            id: resource.id,
            kind: resource.kind,
            role: resource.role,
            originalPath: resource.originalPath,
            originalName: resource.originalName,
            relativePath: resource.relativePath,
            mimeType: resource.mimeType,
            size: resource.size,
            sha256Hash: resource.sha256Hash,
            missing: true,
          ),
        );
        changed = true;
        continue;
      }
      final bytes = await source.readAsBytes();
      final hash = resource.sha256Hash ?? sha256.convert(bytes).toString();
      final location = storageV2ResourceLocation(
        sha256Hash: hash,
        originalName: resource.originalName,
        mimeType: resource.mimeType,
        role: resource.role,
      );
      final target = File('${root.path}/${location.relativePath}');
      if (!await target.exists()) {
        await target.parent.create(recursive: true);
        await target.writeAsBytes(bytes, flush: true);
      }
      upgraded.add(
        StorageV2Resource(
          id: resource.id,
          kind: resource.kind,
          role: resource.role,
          originalPath: resource.originalPath,
          originalName: resource.originalName,
          relativePath: location.relativePath,
          mimeType: resource.mimeType,
          size: bytes.length,
          sha256Hash: hash,
          missing: false,
        ),
      );
      changed = true;
    }

    if (!changed) return;
    await _storageV2.writeDataFile('resources.json', {
      'resources': upgraded.map((resource) => resource.toJson()).toList(),
    });
  }

  bool _isBlobPath(String path) {
    return RegExp(r'^assets/blobs/[a-f0-9]{2}/[a-f0-9]{64}$').hasMatch(path);
  }

  Future<void> _restoreBackup(Directory root, Directory backup) async {
    if (await root.exists()) await root.delete(recursive: true);
    await _copyDirectory(backup, root);
  }

  Future<void> _copyDirectory(Directory source, Directory target) async {
    if (!await target.exists()) await target.create(recursive: true);
    await for (final entity in source.list(recursive: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is Directory) {
        await _copyDirectory(entity, Directory('${target.path}/$name'));
      } else if (entity is File) {
        await entity.copy('${target.path}/$name');
      }
    }
  }
}
