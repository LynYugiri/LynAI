import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import 'ohos_file_picker.dart';
import 'platform_info.dart';

/// User-selected file content from FilePicker.
///
/// Prefer [copyTo] for attachments and large files. Use [readBytes] only when
/// the caller needs the full payload in memory, such as parsing a ZIP archive.
class PickedFilePayload {
  const PickedFilePayload({
    required this.name,
    required this.size,
    this.path,
    this.bytes,
    this.readStream,
  });

  final String name;
  final int size;
  final String? path;
  final Uint8List? bytes;
  final Stream<List<int>>? readStream;

  Future<Uint8List> readBytes() async {
    final inMemory = bytes;
    if (inMemory != null) return inMemory;

    final stream = readStream;
    if (stream != null) {
      final chunks = <int>[];
      await for (final chunk in stream) {
        chunks.addAll(chunk);
      }
      return Uint8List.fromList(chunks);
    }

    final filePath = path;
    if (filePath != null) return File(filePath).readAsBytes();

    throw Exception('无法读取文件内容: $name');
  }

  Future<void> copyTo(File target) async {
    if (!await target.parent.exists()) {
      await target.parent.create(recursive: true);
    }

    final stream = readStream;
    if (stream != null) {
      final sink = target.openWrite();
      try {
        await sink.addStream(stream);
      } finally {
        await sink.close();
      }
      return;
    }

    final inMemory = bytes;
    if (inMemory != null) {
      await target.writeAsBytes(inMemory, flush: true);
      return;
    }

    final filePath = path;
    if (filePath != null) {
      await File(filePath).copy(target.path);
      return;
    }

    throw Exception('无法复制文件内容: $name');
  }

  static PickedFilePayload fromPlatformFile(PlatformFile file) {
    return PickedFilePayload(
      name: file.name,
      size: file.size,
      path: file.path,
      bytes: file.bytes,
      readStream: file.readStream,
    );
  }
}

Future<PickedFilePayload?> pickSingleFilePayload({
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
  bool withData = true,
}) async {
  if (OhosFilePicker.isSupported) {
    final files = await _ohosPicker.pickFiles(
      type: _ohosTypeName(type),
      allowedExtensions: allowedExtensions,
    );
    return files.isEmpty ? null : _ohosPayload(files.first);
  }
  final result = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    type: type,
    allowedExtensions: allowedExtensions,
    withData: withData,
  );
  final file = result?.files.single;
  return file == null ? null : PickedFilePayload.fromPlatformFile(file);
}

Future<List<PickedFilePayload>> pickMultipleFilePayloads({
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  if (OhosFilePicker.isSupported) {
    final files = await _ohosPicker.pickFiles(
      type: _ohosTypeName(type),
      allowedExtensions: allowedExtensions,
      allowMultiple: true,
    );
    return files.map(_ohosPayload).toList(growable: false);
  }
  final result = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    type: type,
    allowedExtensions: allowedExtensions,
    allowMultiple: true,
    withReadStream: true,
  );
  if (result == null) return const [];
  return result.files.map(PickedFilePayload.fromPlatformFile).toList();
}

Future<String?> saveBytesWithPicker({
  required String dialogTitle,
  required String fileName,
  required Uint8List bytes,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
  if (OhosFilePicker.isSupported) {
    // 鸿蒙的系统「另存为」选择器已经把内容写入用户选择的位置，这里返回的是
    // 沙箱内的副本路径（file://docs/... 这类 URI 无法用 dart:io 读取）。
    return _ohosPicker.saveFile(fileName: fileName, bytes: bytes);
  }
  final path = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: type,
    allowedExtensions: allowedExtensions,
    bytes: bytes,
  );
  if (path == null) return null;
  if (!isMobilePlatform) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return path;
}

/// 鸿蒙选择器通道；仅在 [OhosFilePicker.isSupported] 为真时使用。
final OhosFilePicker _ohosPicker = OhosFilePicker();

/// 把 file_picker 的 [FileType] 映射为鸿蒙通道使用的类型名。
String _ohosTypeName(FileType type) =>
    type == FileType.image ? 'image' : 'any';

/// 鸿蒙选择结果与 file_picker 的 [PlatformFile] 语义对齐：路径来自沙箱副本，
/// 因此可以直接交给 `copyTo` / [PickedFilePayload.readBytes]。
PickedFilePayload _ohosPayload(OhosPickedFile file) => PickedFilePayload(
  name: file.name,
  size: file.size,
  path: file.path,
);
