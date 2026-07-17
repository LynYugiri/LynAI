import 'dart:typed_data';

import 'package:archive/archive.dart';

class BoundedZipLimits {
  const BoundedZipLimits({
    required this.maxEntries,
    required this.maxEntryBytes,
    required this.maxTotalBytes,
  });

  final int maxEntries;
  final int maxEntryBytes;
  final int maxTotalBytes;
}

/// Decodes ZIP entries only after validating central-directory metadata.
Archive decodeBoundedZip(
  List<int> bytes, {
  required BoundedZipLimits limits,
  required String archiveLabel,
}) {
  final input = InputMemoryStream(bytes);
  final directory = ZipDirectory()..read(input);
  final headers = directory.fileHeaders;
  if (headers.isEmpty && directory.filePosition < 0) {
    throw FormatException('$archiveLabel格式无效');
  }
  if (directory.totalCentralDirectoryEntries > limits.maxEntries ||
      headers.length > limits.maxEntries) {
    throw FormatException('$archiveLabel条目数超过限制');
  }
  if (directory.totalCentralDirectoryEntries != headers.length) {
    throw FormatException('$archiveLabel中央目录不完整');
  }

  final seen = <String>{};
  var declaredTotal = 0;
  for (final header in headers) {
    final file = header.file;
    if (file == null || file.filename != header.filename) {
      throw FormatException('$archiveLabel文件头不一致');
    }
    final canonicalPath = _canonicalArchivePath(header.filename);
    if (canonicalPath == null) {
      throw FormatException('$archiveLabel包含不安全路径：${header.filename}');
    }
    if (!seen.add(canonicalPath)) {
      throw FormatException('$archiveLabel包含重复条目：${header.filename}');
    }
    if (_isSymbolicLink(header)) {
      throw FormatException('$archiveLabel不允许符号链接：${header.filename}');
    }
    if (header.generalPurposeBitFlag & 0x1 != 0) {
      throw FormatException('$archiveLabel不允许加密条目：${header.filename}');
    }
    if (!const {0, 8, 12}.contains(header.compressionMethod)) {
      throw FormatException('$archiveLabel包含不支持的压缩方法：${header.filename}');
    }
    if (header.compressedSize < 0 || header.compressedSize > bytes.length) {
      throw FormatException('$archiveLabel条目压缩大小无效：${header.filename}');
    }
    if (header.uncompressedSize < 0 ||
        header.uncompressedSize > limits.maxEntryBytes) {
      throw FormatException('$archiveLabel单条解压大小超过限制：${header.filename}');
    }
    if (!_isDirectoryPath(header.filename)) {
      declaredTotal += header.uncompressedSize;
      if (declaredTotal > limits.maxTotalBytes) {
        throw FormatException('$archiveLabel总解压大小超过限制');
      }
    }
  }

  final decoded = ZipDecoder().decodeBytes(bytes);
  if (decoded.length != headers.length) {
    throw FormatException('$archiveLabel条目不完整或重复');
  }
  final archive = Archive();
  var actualTotal = 0;
  for (final entry in decoded) {
    if (entry.isSymbolicLink) {
      throw FormatException('$archiveLabel不允许符号链接：${entry.name}');
    }
    if (!entry.isFile) {
      archive.add(ArchiveFile.directory(entry.name));
      continue;
    }
    final output = _BoundedOutputStream(
      entryLimit: limits.maxEntryBytes,
      totalRemaining: limits.maxTotalBytes - actualTotal,
    );
    try {
      entry.writeContent(output);
    } on _ZipLimitException catch (error) {
      throw FormatException(
        error.total
            ? '$archiveLabel总解压大小超过限制'
            : '$archiveLabel单条解压大小超过限制：${entry.name}',
      );
    }
    final content = output.bytes;
    if (content.length != entry.size) {
      throw FormatException('$archiveLabel条目实际大小与声明不一致：${entry.name}');
    }
    if (entry.crc32 != null && getCrc32(content) != entry.crc32) {
      throw FormatException('$archiveLabel条目校验失败：${entry.name}');
    }
    actualTotal += content.length;
    final extracted = ArchiveFile.bytes(entry.name, content)
      ..mode = entry.mode
      ..crc32 = entry.crc32
      ..lastModTime = entry.lastModTime;
    archive.add(extracted);
  }
  return archive;
}

String? _canonicalArchivePath(String path) {
  if (path.isEmpty || path.contains('\\') || path.startsWith('/')) return null;
  if (RegExp(r'^[A-Za-z]:').hasMatch(path)) return null;
  final directory = _isDirectoryPath(path);
  final normalized = directory ? path.substring(0, path.length - 1) : path;
  if (normalized.isEmpty || normalized.contains('\u0000')) return null;
  final parts = normalized.split('/');
  if (parts.any((part) => part.isEmpty || part == '.' || part == '..')) {
    return null;
  }
  return parts.join('/');
}

bool _isDirectoryPath(String path) => path.endsWith('/');

bool _isSymbolicLink(ZipFileHeader header) {
  if (header.versionMadeBy >> 8 != 3) return false;
  return ((header.externalFileAttributes >> 16) & 0xf000) == 0xa000;
}

class _ZipLimitException implements Exception {
  const _ZipLimitException({required this.total});

  final bool total;
}

class _BoundedOutputStream extends OutputStream {
  _BoundedOutputStream({required this.entryLimit, required this.totalRemaining})
    : super(byteOrder: ByteOrder.littleEndian);

  final int entryLimit;
  final int totalRemaining;
  final BytesBuilder _builder = BytesBuilder(copy: false);

  @override
  int get length => _builder.length;

  Uint8List get bytes => _builder.takeBytes();

  void _check(int count) {
    if (count < 0 || length + count > entryLimit) {
      throw const _ZipLimitException(total: false);
    }
    if (length + count > totalRemaining) {
      throw const _ZipLimitException(total: true);
    }
  }

  @override
  void clear() => _builder.clear();

  @override
  void flush() {}

  @override
  void writeByte(int value) {
    _check(1);
    _builder.addByte(value);
  }

  @override
  void writeBytes(List<int> bytes, {int? length}) {
    final count = length ?? bytes.length;
    if (count > bytes.length) throw RangeError.range(count, 0, bytes.length);
    _check(count);
    _builder.add(count == bytes.length ? bytes : bytes.sublist(0, count));
  }

  @override
  void writeStream(InputStream stream) {
    final count = stream.length;
    _check(count);
    _builder.add(stream.toUint8List());
    stream.skip(count);
  }

  @override
  Uint8List subset(int start, [int? end]) {
    throw UnsupportedError('bounded ZIP output does not support subsets');
  }
}
