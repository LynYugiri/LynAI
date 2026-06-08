import 'dart:io';
import 'dart:typed_data';

import '../utils/file_name_utils.dart';
import '../utils/file_picker_io_utils.dart';
import 'storage_v2_service.dart';

/// Metadata for a file copied into LynAI's private attachment storage.
class StoredAttachment {
  final String path;
  final String name;
  final int size;
  final String mimeType;

  const StoredAttachment({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
  });
}

/// Copies user selected files into app-private storage and returns metadata.
class AttachmentStorageService {
  const AttachmentStorageService({Directory? baseDirectory})
    : _baseDirectory = baseDirectory;

  final Directory? _baseDirectory;

  Future<StoredAttachment> storeFile(
    File source, {
    required String directoryName,
    required String name,
    String fallbackName = 'file',
    String? mimeType,
  }) async {
    final target = await _targetFile(directoryName, name, fallbackName);
    final stored = await source.copy(target.path);
    return StoredAttachment(
      path: stored.path,
      name: name,
      size: await stored.length(),
      mimeType: mimeType ?? inferMimeType(name, fallbackPath: source.path),
    );
  }

  Future<StoredAttachment> storePayload(
    PickedFilePayload source, {
    required String directoryName,
    String fallbackName = 'file',
  }) async {
    final target = await _targetFile(directoryName, source.name, fallbackName);
    await source.copyTo(target);
    return StoredAttachment(
      path: target.path,
      name: source.name,
      size: await target.length(),
      mimeType: inferMimeType(source.name, fallbackPath: source.path),
    );
  }

  Future<StoredAttachment> storeBytes(
    Uint8List bytes, {
    required String directoryName,
    required String name,
    String fallbackName = 'file',
    String? mimeType,
  }) async {
    final target = await _targetFile(directoryName, name, fallbackName);
    await target.writeAsBytes(bytes, flush: true);
    return StoredAttachment(
      path: target.path,
      name: name,
      size: bytes.length,
      mimeType: mimeType ?? inferMimeType(name),
    );
  }

  Future<File> _targetFile(
    String directoryName,
    String name,
    String fallbackName,
  ) async {
    final base =
        _baseDirectory ?? await StorageV2Service.defaultBaseDirectory();
    final directory = Directory('${base.path}/$directoryName');
    if (!await directory.exists()) await directory.create(recursive: true);
    final safeName = safeStorageFileName(name, fallback: fallbackName);
    return File(
      '${directory.path}/${DateTime.now().microsecondsSinceEpoch}_$safeName',
    );
  }

  static String inferMimeType(String path, {String? fallbackPath}) {
    final lower = path.toLowerCase();
    final fallback = fallbackPath?.toLowerCase();
    bool endsWith(String extension) {
      return lower.endsWith(extension) ||
          (fallback?.endsWith(extension) ?? false);
    }

    if (endsWith('.png')) return 'image/png';
    if (endsWith('.jpg') || endsWith('.jpeg')) return 'image/jpeg';
    if (endsWith('.webp')) return 'image/webp';
    if (endsWith('.gif')) return 'image/gif';
    if (endsWith('.pdf')) return 'application/pdf';
    if (endsWith('.txt') || endsWith('.md')) return 'text/plain';
    if (endsWith('.json')) return 'application/json';
    if (endsWith('.csv')) return 'text/csv';
    if (endsWith('.html') || endsWith('.htm')) return 'text/html';
    if (endsWith('.xml')) return 'application/xml';
    if (endsWith('.zip')) return 'application/zip';
    if (endsWith('.doc')) return 'application/msword';
    if (endsWith('.docx')) {
      return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
    }
    if (endsWith('.xls')) return 'application/vnd.ms-excel';
    if (endsWith('.xlsx')) {
      return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
    }
    return 'application/octet-stream';
  }
}
