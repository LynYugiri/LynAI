import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/attachment_storage_service.dart';
import 'package:lynai/utils/file_picker_io_utils.dart';

void main() {
  late Directory tempDir;
  late AttachmentStorageService service;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('lynai_attachment_test_');
    service = AttachmentStorageService(baseDirectory: tempDir);
  });

  tearDown(() async {
    if (await tempDir.exists()) await tempDir.delete(recursive: true);
  });

  test('storeFile copies file into target directory', () async {
    final source = File('${tempDir.path}/source.txt');
    await source.writeAsString('hello');

    final stored = await service.storeFile(
      source,
      directoryName: 'message_attachments',
      name: 'note.txt',
    );

    expect(stored.name, 'note.txt');
    expect(stored.size, 5);
    expect(stored.mimeType, 'text/plain');
    expect(stored.path, contains('/message_attachments/'));
    expect(await File(stored.path).readAsString(), 'hello');
  });

  test('storePayload writes in-memory payload', () async {
    final payload = PickedFilePayload(
      name: 'data.json',
      size: 7,
      bytes: Uint8List.fromList('{"a":1}'.codeUnits),
    );

    final stored = await service.storePayload(
      payload,
      directoryName: 'message_attachments',
    );

    expect(stored.mimeType, 'application/json');
    expect(await File(stored.path).readAsString(), '{"a":1}');
  });

  test('storeBytes writes bytes and keeps explicit mime type', () async {
    final stored = await service.storeBytes(
      Uint8List.fromList([1, 2, 3]),
      directoryName: 'message_images',
      name: 'camera.bin',
      mimeType: 'image/png',
    );

    expect(stored.size, 3);
    expect(stored.mimeType, 'image/png');
    expect(await File(stored.path).readAsBytes(), [1, 2, 3]);
  });

  test('inferMimeType uses fallback path', () {
    expect(
      AttachmentStorageService.inferMimeType(
        'file',
        fallbackPath: 'image.webp',
      ),
      'image/webp',
    );
    expect(
      AttachmentStorageService.inferMimeType('sheet.xlsx'),
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    );
  });
}
