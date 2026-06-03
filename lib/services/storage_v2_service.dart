import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

import '../utils/file_name_utils.dart';
import 'storage_v2_database.dart';

/// Reader/writer facade for the `storage_v2` filesystem layout.
///
/// This keeps UI code away from raw storage paths. Structured data is backed by
/// `app.db`; `data/*.json` remains a legacy/debug mirror and import source.
class StorageV2Service {
  StorageV2Service({Directory? rootDirectory}) : _rootDirectory = rootDirectory;

  final Directory? _rootDirectory;
  StorageV2Database? _database;
  Future<void> _resourceMutationQueue = Future.value();

  Future<bool> exists() async {
    return (await probe()).ready;
  }

  Future<StorageV2ProbeResult> probe() async {
    final root = await _storageRoot();
    final manifest = File('${root.path}/manifest.json');
    if (!await manifest.exists()) {
      return const StorageV2ProbeResult(StorageV2ProbeStatus.missing);
    }
    try {
      final json = jsonDecode(await manifest.readAsString());
      if (json is! Map) {
        return const StorageV2ProbeResult(StorageV2ProbeStatus.invalidManifest);
      }
      final type = json['type'];
      if (type != 'lynai.storage_v2') {
        return const StorageV2ProbeResult(StorageV2ProbeStatus.invalidManifest);
      }
      final version = (json['schemaVersion'] as num?)?.toInt();
      if (version == null || version > 2) {
        return const StorageV2ProbeResult(
          StorageV2ProbeStatus.incompatibleVersion,
        );
      }
      final database = File('${root.path}/app.db');
      final dataDir = Directory('${root.path}/data');
      if (!await database.exists() && !await dataDir.exists()) {
        return const StorageV2ProbeResult(StorageV2ProbeStatus.incomplete);
      }
      return StorageV2ProbeResult(StorageV2ProbeStatus.ready, version: version);
    } catch (e) {
      return StorageV2ProbeResult(
        StorageV2ProbeStatus.invalidManifest,
        message: '$e',
      );
    }
  }

  Future<Map<String, dynamic>> loadManifest() async {
    return _readMap('manifest.json');
  }

  Future<StorageV2NotesSnapshot> loadNotes() async {
    final json = await loadNotesData();
    final notes = (json['notes'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map((item) => StorageV2Note.fromJson(Map<String, dynamic>.from(item)))
        .toList();
    final pages =
        (json['pages'] as List<dynamic>? ?? const [])
            .whereType<Map>()
            .map(
              (item) =>
                  StorageV2NotePage.fromJson(Map<String, dynamic>.from(item)),
            )
            .toList()
          ..sort((a, b) {
            final noteCompare = a.noteId.compareTo(b.noteId);
            if (noteCompare != 0) return noteCompare;
            return a.sortOrder.compareTo(b.sortOrder);
          });
    return StorageV2NotesSnapshot(notes: notes, pages: pages);
  }

  Future<Map<String, dynamic>> loadDataFile(String fileName) {
    return _loadDataFile(fileName);
  }

  Future<void> writeDataFile(String fileName, Map<String, dynamic> data) async {
    final database = await _storageDatabase();
    await database.writeDataFile(fileName, data);
    try {
      await _writeMap('data/$fileName', data);
    } catch (e) {
      // `data/*.json` is only a legacy/debug mirror; app.db is authoritative.
      debugPrint('storage_v2 JSON mirror write failed for $fileName: $e');
    }
  }

  Future<Map<String, dynamic>> loadNotesData() {
    return loadDataFile('notes.json');
  }

  Future<void> writeNotesData(Map<String, dynamic> data) async {
    await writeDataFile('notes.json', data);
  }

  Future<bool> databaseExists() async {
    final database = await _storageDatabase();
    return database.exists();
  }

  Future<void> importDataFilesToDatabase({bool overwrite = false}) async {
    final database = await _storageDatabase();
    await database.importDataFiles(overwrite: overwrite);
  }

  Future<String> readNotePage(StorageV2NotePage page) async {
    final file = await _file(page.relativePath);
    return file.readAsString();
  }

  Future<void> writeNotePage(StorageV2NotePage page, String content) async {
    final file = await _file(page.relativePath);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    final tmp = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await tmp.writeAsString(content, flush: true);
      await tmp.rename(file.path);
    } catch (_) {
      if (await tmp.exists()) await tmp.delete();
      rethrow;
    }
  }

  Future<void> deleteFile(String relativePath) async {
    final file = await _file(relativePath);
    if (await file.exists()) await file.delete();
  }

  Future<List<StorageV2Resource>> loadResources() async {
    final json = await loadDataFile('resources.json');
    return (json['resources'] as List<dynamic>? ?? const [])
        .whereType<Map>()
        .map(
          (item) => StorageV2Resource.fromJson(Map<String, dynamic>.from(item)),
        )
        .toList();
  }

  Future<StorageV2Resource?> findResourceByPath(String path) async {
    final normalizedPath = _normalizePath(File(path).absolute.path);
    for (final resource in await loadResources()) {
      final file = await resourceFile(resource);
      if (file == null) continue;
      if (_normalizePath(file.absolute.path) == normalizedPath) return resource;
    }
    return null;
  }

  Future<StorageV2Resource?> findResourceById(String id) async {
    for (final resource in await loadResources()) {
      if (resource.id == id) return resource;
    }
    return null;
  }

  Future<StorageV2Resource> importResourceFile(
    String path, {
    required String originalName,
    required String mimeType,
    required String role,
  }) async {
    return _runResourceMutation(() async {
      final existingByPath = await findResourceByPath(path);
      if (existingByPath != null) return existingByPath;

      final resources = await loadResources();
      final file = File(path);
      final exists = path.isNotEmpty && await file.exists();
      if (!exists) {
        for (final resource in resources) {
          if (resource.missing &&
              resource.originalPath == path &&
              resource.originalName == originalName &&
              resource.role == role) {
            return resource;
          }
        }
      }
      final resource = exists
          ? await _importExistingResource(
              file,
              resources,
              originalName,
              mimeType,
              role,
            )
          : _missingResource(path, originalName, mimeType, role);
      if (resources.any((item) => item.id == resource.id)) return resource;
      await writeDataFile('resources.json', {
        'resources': [...resources.map((e) => e.toJson()), resource.toJson()],
      });
      return resource;
    });
  }

  Future<T> _runResourceMutation<T>(Future<T> Function() action) {
    // Resource imports append to a read-modify-write snapshot, so keep one
    // mutation active per service instance to avoid dropping concurrent rows.
    late T result;
    final run = _resourceMutationQueue
        .catchError((_) {})
        .then((_) async => result = await action());
    _resourceMutationQueue = run.then<void>((_) {});
    return run.then((_) => result);
  }

  Future<File?> resourceFile(StorageV2Resource resource) async {
    final path = resource.relativePath;
    if (path == null || resource.missing) return null;
    return _file(path);
  }

  Future<String?> resourcePath(StorageV2Resource resource) async {
    final file = await resourceFile(resource);
    return file?.path;
  }

  Future<Map<String, dynamic>> _readMap(String relativePath) async {
    final file = await _file(relativePath);
    final content = await file.readAsString();
    return jsonDecode(content) as Map<String, dynamic>;
  }

  Future<Map<String, dynamic>> _loadDataFile(String fileName) async {
    final database = await _storageDatabase();
    if (!await database.hasImportedDataFiles()) {
      await database.importDataFiles();
    }
    final data = await database.loadDataFile(fileName);
    if (data != null) return data;
    final legacy = await _readMap('data/$fileName');
    await database.writeDataFile(fileName, legacy);
    return legacy;
  }

  Future<void> _writeMap(
    String relativePath,
    Map<String, dynamic> value,
  ) async {
    final file = await _file(relativePath);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await file.writeAsString(
      const JsonEncoder.withIndent('  ').convert(value),
      flush: true,
    );
  }

  Future<File> _file(String relativePath) async {
    final root = await _storageRoot();
    final normalized = relativePath.replaceAll('\\', '/');
    final parts = normalized.split('/');
    if (normalized.startsWith('/') ||
        parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw ArgumentError('Unsafe storage path: $relativePath');
    }
    final file = File('${root.path}/$normalized');
    final rootPath = _normalizePath(root.absolute.path);
    final filePath = _normalizePath(file.absolute.path);
    if (filePath != rootPath && !filePath.startsWith('$rootPath/')) {
      throw ArgumentError('Storage path escapes root: $relativePath');
    }
    return file;
  }

  Future<StorageV2Resource> _importExistingResource(
    File file,
    List<StorageV2Resource> resources,
    String originalName,
    String mimeType,
    String role,
  ) async {
    final bytes = await file.readAsBytes();
    final hash = sha256.convert(bytes).toString();
    for (final resource in resources) {
      if (!resource.missing &&
          resource.sha256Hash == hash &&
          resource.size == bytes.length) {
        await _ensureResourceFile(resource, bytes);
        return resource;
      }
    }

    final kind = _resourceKind(mimeType, role);
    final safeName = safeExportFileName(originalName, fallback: 'asset');
    final prefix = hash.substring(0, 2);
    final storedName = '${hash}_$safeName';
    final relativePath = 'assets/$kind/$prefix/$storedName';
    final target = await _file(relativePath);
    final parent = target.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    if (_normalizePath(file.absolute.path) !=
        _normalizePath(target.absolute.path)) {
      await target.writeAsBytes(bytes, flush: true);
    }

    return StorageV2Resource(
      id: 'res_${hash.substring(0, 32)}',
      kind: kind,
      role: role,
      originalPath: file.path,
      originalName: originalName,
      relativePath: relativePath,
      mimeType: mimeType,
      size: bytes.length,
      sha256Hash: hash,
      missing: false,
    );
  }

  Future<void> _ensureResourceFile(
    StorageV2Resource resource,
    List<int> bytes,
  ) async {
    final path = resource.relativePath;
    if (path == null || resource.missing) return;
    final target = await _file(path);
    if (await target.exists()) return;
    final parent = target.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    await target.writeAsBytes(bytes, flush: true);
  }

  StorageV2Resource _missingResource(
    String path,
    String originalName,
    String mimeType,
    String role,
  ) {
    final hash = sha256.convert(utf8.encode('$path|$originalName')).toString();
    return StorageV2Resource(
      id: 'missing_${hash.substring(0, 32)}',
      kind: _resourceKind(mimeType, role),
      role: role,
      originalPath: path,
      originalName: originalName,
      relativePath: null,
      mimeType: mimeType,
      size: 0,
      sha256Hash: null,
      missing: true,
    );
  }

  Future<Directory> _storageRoot() async {
    final injectedRoot = _rootDirectory;
    if (injectedRoot != null) {
      return Directory('${injectedRoot.path}/storage_v2');
    }

    final supportRoot = Directory(
      '${(await defaultBaseDirectory()).path}/storage_v2',
    );
    if (await supportRoot.exists()) return supportRoot;

    final documentsRoot = Directory(
      '${(await getApplicationDocumentsDirectory()).path}/storage_v2',
    );
    if (!await documentsRoot.exists()) return supportRoot;

    return _moveLegacyDocumentsStorage(documentsRoot, supportRoot);
  }

  static Future<Directory> defaultBaseDirectory() async {
    try {
      final support = await getApplicationSupportDirectory();
      if (!await support.exists()) await support.create(recursive: true);
      return support;
    } catch (_) {
      final documents = await getApplicationDocumentsDirectory();
      if (!await documents.exists()) await documents.create(recursive: true);
      return documents;
    }
  }

  Future<Directory> _moveLegacyDocumentsStorage(
    Directory from,
    Directory to,
  ) async {
    if (!await to.parent.exists()) await to.parent.create(recursive: true);
    try {
      return await from.rename(to.path);
    } catch (e) {
      try {
        await _copyDirectory(from, to);
        await from.delete(recursive: true);
        return to;
      } catch (copyError) {
        debugPrint(
          'storage_v2 move to support directory failed: $e; $copyError',
        );
        return from;
      }
    }
  }

  Future<void> _copyDirectory(Directory from, Directory to) async {
    if (!await to.exists()) await to.create(recursive: true);
    await for (final entity in from.list(recursive: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is Directory) {
        await _copyDirectory(entity, Directory('${to.path}/$name'));
      } else if (entity is File) {
        await entity.copy('${to.path}/$name');
      }
    }
  }

  Future<StorageV2Database> _storageDatabase() async {
    final existing = _database;
    if (existing != null) return existing;
    final database = StorageV2Database(await _storageRoot());
    _database = database;
    return database;
  }

  static String _normalizePath(String path) => path.replaceAll('\\', '/');
}

enum StorageV2ProbeStatus {
  missing,
  invalidManifest,
  incompatibleVersion,
  incomplete,
  ready,
}

class StorageV2ProbeResult {
  final StorageV2ProbeStatus status;
  final int? version;
  final String? message;

  const StorageV2ProbeResult(this.status, {this.version, this.message});

  bool get ready => status == StorageV2ProbeStatus.ready;
}

class StorageV2NotesSnapshot {
  final List<StorageV2Note> notes;
  final List<StorageV2NotePage> pages;

  const StorageV2NotesSnapshot({required this.notes, required this.pages});

  List<StorageV2NotePage> pagesFor(String noteId) {
    return pages.where((page) => page.noteId == noteId).toList();
  }
}

class StorageV2Note {
  final String id;
  final String title;
  final String? folderId;
  final String? currentRevisionId;
  final String? currentPageId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool wrap;

  const StorageV2Note({
    required this.id,
    required this.title,
    this.folderId,
    this.currentRevisionId,
    this.currentPageId,
    required this.createdAt,
    required this.updatedAt,
    required this.wrap,
  });

  factory StorageV2Note.fromJson(Map<String, dynamic> json) {
    return StorageV2Note(
      id: json['id'] as String,
      title: json['title'] as String? ?? '',
      folderId: json['folderId'] as String?,
      currentRevisionId: json['currentRevisionId'] as String?,
      currentPageId: json['currentPageId'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
      wrap: json['wrap'] as bool? ?? true,
    );
  }
}

class StorageV2NotePage {
  final String id;
  final String noteId;
  final String title;
  final String fileName;
  final String relativePath;
  final String? currentRevisionId;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;

  const StorageV2NotePage({
    required this.id,
    required this.noteId,
    required this.title,
    required this.fileName,
    required this.relativePath,
    this.currentRevisionId,
    required this.sortOrder,
    required this.createdAt,
    required this.updatedAt,
  });

  factory StorageV2NotePage.fromJson(Map<String, dynamic> json) {
    return StorageV2NotePage(
      id: json['id'] as String,
      noteId: json['noteId'] as String,
      title: json['title'] as String? ?? '',
      fileName: json['fileName'] as String? ?? '',
      relativePath: json['relativePath'] as String,
      currentRevisionId: json['currentRevisionId'] as String?,
      sortOrder: json['sortOrder'] as int? ?? 0,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: DateTime.parse(json['updatedAt'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'noteId': noteId,
    'title': title,
    'fileName': fileName,
    'relativePath': relativePath,
    if (currentRevisionId != null) 'currentRevisionId': currentRevisionId,
    'sortOrder': sortOrder,
    'createdAt': createdAt.toIso8601String(),
    'updatedAt': updatedAt.toIso8601String(),
  };
}

class StorageV2Resource {
  final String id;
  final String kind;
  final String role;
  final String originalPath;
  final String originalName;
  final String? relativePath;
  final String mimeType;
  final int size;
  final String? sha256Hash;
  final bool missing;

  const StorageV2Resource({
    required this.id,
    required this.kind,
    required this.role,
    required this.originalPath,
    required this.originalName,
    required this.relativePath,
    required this.mimeType,
    required this.size,
    required this.sha256Hash,
    required this.missing,
  });

  factory StorageV2Resource.fromJson(Map<String, dynamic> json) {
    return StorageV2Resource(
      id: json['id'] as String,
      kind: json['kind'] as String? ?? 'unknown',
      role: json['role'] as String? ?? 'unknown',
      originalPath: json['originalPath'] as String? ?? '',
      originalName: json['originalName'] as String? ?? 'file',
      relativePath: json['relativePath'] as String?,
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      size: json['size'] as int? ?? 0,
      sha256Hash: json['sha256'] as String?,
      missing: json['missing'] as bool? ?? false,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'role': role,
    'originalPath': originalPath,
    'originalName': originalName,
    if (relativePath != null) 'relativePath': relativePath,
    'mimeType': mimeType,
    'size': size,
    if (sha256Hash != null) 'sha256': sha256Hash,
    'missing': missing,
  };
}

String _resourceKind(String mimeType, String role) {
  if (role == 'background') return 'backgrounds';
  if (mimeType.startsWith('image/')) return 'images';
  if (mimeType.startsWith('audio/')) return 'audio';
  if (mimeType.startsWith('video/')) return 'video';
  if (mimeType == 'application/octet-stream') return 'unknown';
  return 'documents';
}
