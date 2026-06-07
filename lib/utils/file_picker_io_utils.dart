import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

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
}) async {
  final result = await FilePicker.pickFiles(
    dialogTitle: dialogTitle,
    type: type,
    allowedExtensions: allowedExtensions,
    withData: true,
  );
  final file = result?.files.single;
  return file == null ? null : PickedFilePayload.fromPlatformFile(file);
}

Future<List<PickedFilePayload>> pickMultipleFilePayloads({
  String? dialogTitle,
  FileType type = FileType.any,
  List<String>? allowedExtensions,
}) async {
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
  final path = await FilePicker.saveFile(
    dialogTitle: dialogTitle,
    fileName: fileName,
    type: type,
    allowedExtensions: allowedExtensions,
    bytes: bytes,
  );
  if (path == null) return null;
  if (!Platform.isAndroid && !Platform.isIOS) {
    await File(path).writeAsBytes(bytes, flush: true);
  }
  return path;
}
