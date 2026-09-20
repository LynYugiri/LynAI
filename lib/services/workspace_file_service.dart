import 'dart:convert';
import 'dart:io';

/// 挂载目录中的一个条目。
class WorkspaceFileEntry {
  final String name;
  final String path;
  final bool isDirectory;
  final int size;

  const WorkspaceFileEntry({
    required this.name,
    required this.path,
    required this.isDirectory,
    this.size = 0,
  });
}

/// 工作区挂载真实本地文件夹的读写服务。
///
/// 只接受规范化相对路径，所有写路径先做符号链接解析并与挂载根比较，
/// 拒绝任何逃逸挂载根的操作。列目录不跟随符号链接。
class WorkspaceFileService {
  const WorkspaceFileService();

  static const maxListEntries = 1000;
  static const maxReadChars = 200000;
  static const maxWriteChars = 5000000;
  static const _binaryProbeBytes = 8192;

  Future<bool> isMountedFolderUsable(String root) async {
    try {
      final directory = Directory(root);
      if (!await directory.exists()) return false;
      await directory.resolveSymbolicLinks();
      return true;
    } catch (_) {
      return false;
    }
  }

  /// 列出挂载目录中的单层条目。
  ///
  /// 目录优先、按名字排序；条目达到 [maxListEntries] 即停止枚举。
  Future<List<WorkspaceFileEntry>> listDirectory(
    String root,
    String relativeDir,
  ) async {
    final directory = await _resolveDirectory(root, relativeDir);
    final entities = <FileSystemEntity>[];
    await for (final entity in directory.list(
      followLinks: false,
      recursive: false,
    )) {
      if (entity is Link) continue;
      entities.add(entity);
      if (entities.length >= maxListEntries) break;
    }
    final entries = <WorkspaceFileEntry>[];
    for (final entity in entities) {
      final stat = await entity.stat();
      final isDirectory = entity is Directory;
      entries.add(
        WorkspaceFileEntry(
          name: _baseName(entity.path),
          path: _joinRelative(relativeDir, _baseName(entity.path)),
          isDirectory: isDirectory,
          size: isDirectory ? 0 : stat.size,
        ),
      );
    }
    entries.sort((a, b) {
      if (a.isDirectory != b.isDirectory) return a.isDirectory ? -1 : 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return entries;
  }

  /// 读取挂载目录中的文本文件。
  ///
  /// 前 [WorkspaceFileService._binaryProbeBytes] 字节含 NUL 时按二进制拒绝；
  /// 返回内容按 [maxReadChars] 截断。
  Future<String> readTextFile(
    String root,
    String relativePath, {
    int maxChars = maxReadChars,
  }) async {
    final file = await _resolveFile(root, relativePath);
    final limit = (maxChars.clamp(1, maxReadChars)) * 4 + _binaryProbeBytes;
    final bytes = <int>[];
    await for (final chunk in file.openRead(0, limit)) {
      bytes.addAll(chunk);
      if (bytes.length >= limit) break;
    }
    if (_looksBinary(bytes)) {
      throw const FileSystemException('文件是二进制内容，暂不支持文本预览');
    }
    final text = utf8.decode(bytes, allowMalformed: true);
    return text.length <= maxChars ? text : text.substring(0, maxChars);
  }

  /// 原子写入挂载目录中的文本文件（临时文件 + rename）。
  Future<void> writeTextFile(
    String root,
    String relativePath,
    String content,
  ) async {
    if (content.length > maxWriteChars) {
      throw const FileSystemException('文本内容超过工作区单文件写入上限');
    }
    final file = await _resolveFile(root, relativePath, forWrite: true);
    final parent = file.parent;
    if (!await parent.exists()) await parent.create(recursive: true);
    final temporary = File(
      '${file.path}.tmp.${DateTime.now().microsecondsSinceEpoch}',
    );
    try {
      await temporary.writeAsString(content, flush: true);
      await temporary.rename(file.path);
    } catch (_) {
      if (await temporary.exists()) await temporary.delete();
      rethrow;
    }
  }

  /// 把用户输入路径规范化为工作区相对路径；不安全返回 null。
  static String? normalizeRelative(String value) {
    var normalized = value.replaceAll('\\', '/').trim();
    if (normalized == '.' || normalized == '') normalized = '';
    if (normalized.startsWith('/') ||
        RegExp(r'^[A-Za-z]:').hasMatch(normalized)) {
      return null;
    }
    if (normalized.endsWith('/')) {
      normalized = normalized.substring(0, normalized.length - 1);
    }
    final parts = normalized.split('/');
    if (parts.any((part) => part == '.' || part == '..' || part.isEmpty)) {
      return normalized.isEmpty ? '' : null;
    }
    return normalized;
  }

  static String _joinRelative(String directory, String name) {
    final base = directory.isEmpty ? '' : '$directory/';
    return '$base$name';
  }

  static String _baseName(String path) {
    final normalized = path.replaceAll('\\', '/');
    final index = normalized.lastIndexOf('/');
    return index == -1 ? normalized : normalized.substring(index + 1);
  }

  static bool _looksBinary(List<int> bytes) {
    final probe = bytes.length > _binaryProbeBytes
        ? bytes.sublist(0, _binaryProbeBytes)
        : bytes;
    return probe.contains(0);
  }

  static String _normalizeAbsolute(String path) {
    final absolute = File(path).absolute.path.replaceAll('\\', '/');
    return Platform.isWindows ? absolute.toLowerCase() : absolute;
  }

  Future<Directory> _resolveDirectory(String root, String relativeDir) async {
    final relative = normalizeRelative(relativeDir);
    if (relative == null) {
      throw const FileSystemException('目录路径不安全');
    }
    final rootDirectory = Directory(root);
    if (!await rootDirectory.exists()) {
      throw const FileSystemException('挂载目录不存在');
    }
    final canonicalRoot = await rootDirectory.resolveSymbolicLinks();
    final target = Directory(
      relative.isEmpty ? rootDirectory.path : '${rootDirectory.path}/$relative',
    );
    final canonicalTarget = await target.resolveSymbolicLinks();
    final targetRoot = _normalizeAbsolute(canonicalTarget);
    final rootPath = _normalizeAbsolute(canonicalRoot);
    if (targetRoot != rootPath && !targetRoot.startsWith('$rootPath/')) {
      throw const FileSystemException('目录路径逃逸挂载根');
    }
    return target;
  }

  Future<File> _resolveFile(
    String root,
    String relativePath, {
    bool forWrite = false,
  }) async {
    final relative = normalizeRelative(relativePath);
    if (relative == null || relative.isEmpty) {
      throw const FileSystemException('文件路径不安全');
    }
    final rootDirectory = Directory(root);
    if (!await rootDirectory.exists()) {
      throw const FileSystemException('挂载目录不存在');
    }
    final canonicalRoot = _normalizeAbsolute(
      await rootDirectory.resolveSymbolicLinks(),
    );
    final file = File('${rootDirectory.path}/$relative');
    if (forWrite) {
      var ancestor = file.parent;
      while (!await ancestor.exists()) {
        final parent = ancestor.parent;
        if (_normalizeAbsolute(parent.path) ==
            _normalizeAbsolute(ancestor.path)) {
          break;
        }
        ancestor = parent;
      }
      final canonicalAncestor = _normalizeAbsolute(
        await ancestor.resolveSymbolicLinks(),
      );
      if (canonicalAncestor != canonicalRoot &&
          !canonicalAncestor.startsWith('$canonicalRoot/')) {
        throw const FileSystemException('文件路径逃逸挂载根');
      }
      return file;
    }
    if (!await file.exists()) {
      throw FileSystemException('文件不存在: $relative');
    }
    final canonicalFile = _normalizeAbsolute(await file.resolveSymbolicLinks());
    if (canonicalFile != canonicalRoot &&
        !canonicalFile.startsWith('$canonicalRoot/')) {
      throw const FileSystemException('文件路径逃逸挂载根');
    }
    return file;
  }
}
