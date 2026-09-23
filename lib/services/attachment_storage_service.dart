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

  /// 应用私有存储中对应的 Resource ID，导入失败或未导入时为空。
  final String? resourceId;

  const StoredAttachment({
    required this.path,
    required this.name,
    required this.size,
    required this.mimeType,
    this.resourceId,
  });
}

/// Copies user selected files into app-private storage and returns metadata.
///
/// 传入 `resourceRole` 时，文件复制完成后会顺带导入成 storage_v2 Resource：内容是
/// 哈希去重的，所以同一份文件在发送或再次导入时复用同一条 Resource 与同一份 blob。
/// 聊天附件依赖这条 Resource 记录实现草稿跨设备恢复（见 `ComposerDraftAttachment`）；
/// 其他调用方（情景演绎、插件函数）不传就保持纯文件暂存。
class AttachmentStorageService {
  const AttachmentStorageService({
    Directory? baseDirectory,
    StorageV2Service? storageV2,
  }) : _baseDirectory = baseDirectory,
       _storageV2 = storageV2;

  final Directory? _baseDirectory;
  final StorageV2Service? _storageV2;

  Future<StoredAttachment> storeFile(
    File source, {
    required String directoryName,
    required String name,
    String fallbackName = 'file',
    String? mimeType,
    String? resourceRole,
  }) async {
    final target = await _targetFile(directoryName, name, fallbackName);
    final stored = await source.copy(target.path);
    return _stored(
      path: stored.path,
      name: name,
      size: await stored.length(),
      mimeType: mimeType ?? inferMimeType(name, fallbackPath: source.path),
      role: resourceRole,
    );
  }

  Future<StoredAttachment> storePayload(
    PickedFilePayload source, {
    required String directoryName,
    String fallbackName = 'file',
    String? resourceRole,
  }) async {
    final target = await _targetFile(directoryName, source.name, fallbackName);
    await source.copyTo(target);
    return _stored(
      path: target.path,
      name: source.name,
      size: await target.length(),
      mimeType: inferMimeType(source.name, fallbackPath: source.path),
      role: resourceRole,
    );
  }

  Future<StoredAttachment> storeBytes(
    Uint8List bytes, {
    required String directoryName,
    required String name,
    String fallbackName = 'file',
    String? mimeType,
    String? resourceRole,
  }) async {
    final target = await _targetFile(directoryName, name, fallbackName);
    await target.writeAsBytes(bytes, flush: true);
    return _stored(
      path: target.path,
      name: name,
      size: bytes.length,
      mimeType: mimeType ?? inferMimeType(name),
      role: resourceRole,
    );
  }

  /// 按需导入 Resource 并返回附件元数据；导入失败不阻塞附件暂存。
  Future<StoredAttachment> _stored({
    required String path,
    required String name,
    required int size,
    required String mimeType,
    required String? role,
  }) async {
    String? resourceId;
    final storage = _storageV2;
    if (storage != null && role != null) {
      try {
        resourceId = (await storage.importResourceFile(
          path,
          originalName: name,
          mimeType: mimeType,
          role: role,
        )).id;
      } catch (_) {
        resourceId = null;
      }
    }
    return StoredAttachment(
      path: path,
      name: name,
      size: size,
      mimeType: mimeType,
      resourceId: resourceId,
    );
  }

  /// 聊天附件使用的 Resource 角色：图片与文件分开，两者都参与同步。
  static String messageResourceRole(String mimeType) =>
      mimeType.startsWith('image/') ? 'message_image' : 'message_attachment';

  Future<File> _targetFile(
    String directoryName,
    String name,
    String fallbackName,
  ) async {
    final base =
        _baseDirectory ??
        (_storageV2 == null
            ? await StorageV2Service.defaultBaseDirectory()
            : (await _storageV2.storageRoot()).parent);
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
