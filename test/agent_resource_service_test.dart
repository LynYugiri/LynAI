import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/services/agent_resource_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';

void main() {
  late Directory root;
  late Directory sourceRoot;
  late StorageV2Service storage;
  late AgentResourceService service;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_resource_read_test_');
    sourceRoot = await Directory.systemTemp.createTemp(
      'lynai_resource_read_source_test_',
    );
    storage = StorageV2Service(rootDirectory: root);
    service = AgentResourceService(
      storage: storage,
      conversationId: 'conversation',
      findConversation: (_) async => _conversation,
    );
  });

  tearDown(() async {
    if (await root.exists()) await root.delete(recursive: true);
    if (await sourceRoot.exists()) await sourceRoot.delete(recursive: true);
  });

  test('reads text by resource ID with byte and character bounds', () async {
    final resource = await _import(
      storage,
      sourceRoot,
      name: 'notes.txt',
      content: 'abcdef',
    );

    final byBytes = await service.readText(resource.id, maxBytes: 4);
    final byChars = await service.readText(resource.id, maxChars: 3);

    expect(byBytes.text, 'abcd');
    expect(byBytes.truncated, isTrue);
    expect(byChars.text, 'abc');
    expect(byChars.truncated, isTrue);
    expect(byBytes.metadata.name, 'notes.txt');
  });

  test('metadata does not expose storage paths or hashes', () async {
    final resource = await _import(
      storage,
      sourceRoot,
      name: 'private.txt',
      content: 'secret',
      originalName: r'C:\Users\person\private.txt',
    );

    final metadata = await service.metadata(resource.id);
    final rendered = metadata.toString();

    expect(metadata.id, resource.id);
    expect(metadata.name, 'private.txt');
    expect(rendered, isNot(contains(sourceRoot.path)));
    expect(rendered, isNot(contains(resource.relativePath!)));
    expect(rendered, isNot(contains(resource.sha256Hash!)));
  });

  test('rejects a readable resource owned by another conversation', () async {
    final resource = await _import(
      storage,
      sourceRoot,
      name: 'other.txt',
      content: 'other',
    );
    _conversation = Conversation(
      id: 'conversation',
      title: 'empty',
      messages: const [],
      modelId: 'model',
      createdAt: DateTime.utc(2026),
      updatedAt: DateTime.utc(2026),
    );

    await expectLater(
      service.metadata(resource.id),
      throwsA(
        isA<AgentResourceException>().having(
          (error) => error.code,
          'code',
          'not_found',
        ),
      ),
    );
  });

  test('rejects non-message roles and non-text MIME types', () async {
    final background = await _import(
      storage,
      sourceRoot,
      name: 'background.txt',
      content: 'hidden',
      role: 'background',
    );
    final image = await _import(
      storage,
      sourceRoot,
      name: 'image.png',
      content: 'not really an image',
      mimeType: 'image/png',
      role: 'message_image',
    );

    await expectLater(
      service.metadata(background.id),
      throwsA(
        isA<AgentResourceException>().having(
          (error) => error.code,
          'code',
          'forbidden_role',
        ),
      ),
    );
    await expectLater(
      service.readText(image.id),
      throwsA(
        isA<AgentResourceException>().having(
          (error) => error.code,
          'code',
          'unsupported_mime',
        ),
      ),
    );
  });

  test(
    'search is role-filtered, bounded, and returns redacted metadata',
    () async {
      await _import(
        storage,
        sourceRoot,
        name: 'alpha-notes.txt',
        content: 'one',
      );
      await _import(
        storage,
        sourceRoot,
        name: 'alpha-background.txt',
        content: 'two',
        role: 'background',
      );
      await _import(
        storage,
        sourceRoot,
        name: 'alpha-log.txt',
        content: 'three',
      );

      final results = await service.search('alpha', limit: 1);

      expect(results, hasLength(1));
      expect(AgentResourceService.readableRoles, contains(results.single.role));
      expect(() => service.search('alpha', limit: 51), throwsArgumentError);
    },
  );
}

Conversation? _conversation;

Future<StorageV2Resource> _import(
  StorageV2Service storage,
  Directory sourceRoot, {
  required String name,
  required String content,
  String? originalName,
  String mimeType = 'text/plain',
  String role = 'message_attachment',
}) async {
  final file = File('${sourceRoot.path}/$name');
  await file.writeAsString(content, flush: true);
  return storage
      .importResourceFile(
        file.path,
        originalName: originalName ?? name,
        mimeType: mimeType,
        role: role,
      )
      .then((resource) async {
        final path = await storage.resourcePath(resource);
        final now = DateTime.now();
        _conversation = Conversation(
          id: 'conversation',
          title: 'test',
          messages: [
            ...?_conversation?.messages,
            Message(
              id: resource.id,
              role: 'user',
              content: '',
              images: [
                MessageImage(
                  path: path ?? '',
                  name: originalName ?? name,
                  size: resource.size,
                  mimeType: mimeType,
                ),
              ],
              timestamp: now,
            ),
          ],
          modelId: 'model',
          createdAt: now,
          updatedAt: now,
        );
        return resource;
      });
}
