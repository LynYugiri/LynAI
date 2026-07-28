import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/services/agent_cancellation.dart';
import 'package:lynai/services/agent_tool_result_sanitizer.dart';
import 'package:lynai/services/backup_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory root;
  late StorageV2Service storage;
  late AgentToolResultSanitizer sanitizer;

  setUp(() async {
    root = await Directory.systemTemp.createTemp('lynai_agent_result_test_');
    storage = StorageV2Service(rootDirectory: root);
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
    sanitizer = AgentToolResultSanitizer.storageV2(
      storage,
      limits: const AgentToolResultSanitizerLimits(
        maxInlineBytes: 512,
        maxOffloadBytes: 4096,
        previewChars: 32,
      ),
    );
  });

  tearDown(() async {
    await storage.close();
    if (await root.exists()) await root.delete(recursive: true);
  });

  test('keeps small JSON inline and bounds malformed values', () async {
    final cyclic = <Object?>[];
    cyclic.add(cyclic);

    final result = await sanitizer.sanitize({
      'ok': true,
      'nan': double.nan,
      'unsupported': Object(),
      'cycle': cyclic,
      'password': 'must-not-leak',
    });

    expect(result.resources, isEmpty);
    expect(result.value, {
      'ok': true,
      'nan': 'NaN',
      'unsupported': '[UNSUPPORTED: Object]',
      'cycle': ['[REDACTED: cyclic value]'],
      'password': '[REDACTED]',
    });
  });

  test(
    'processor sanitizes terminal values while preserving correlation',
    () async {
      final processor = SanitizingAgentToolResultProcessor(sanitizer);
      final cancellation = AgentCancellationSource();

      final results = await processor.process([
        AgentToolResult.success(
          invocationId: 'success',
          toolName: 'lookup',
          value: const {'apiKey': 'secret'},
        ),
        AgentToolResult.failure(
          invocationId: 'failure',
          toolName: 'lookup',
          code: 'failed',
          message: 'safe error',
          value: const {'token': 'secret'},
        ),
        AgentToolResult.cancelled(
          invocationId: 'cancelled',
          toolName: 'lookup',
          message: 'cancelled',
        ),
      ], cancellationToken: cancellation.token);

      expect(results[0].invocationId, 'success');
      expect(results[0].value, {'apiKey': '[REDACTED]'});
      expect(results[1].status, AgentToolResultStatus.failure);
      expect(results[1].errorCode, 'failed');
      expect(results[1].value, {'token': '[REDACTED]'});
      expect(results[2].status, AgentToolResultStatus.cancelled);
    },
  );

  test('deduplicates offloaded text and returns path-free metadata', () async {
    final text = 'large result ${'x' * 1000} /home/person/private/data.txt';

    final first = await sanitizer.sanitize(text);
    final second = await sanitizer.sanitize(text);

    expect(first.resources, hasLength(1));
    expect(second.resources.single.id, first.resources.single.id);
    expect(await storage.loadResources(), hasLength(1));
    final rendered = jsonEncode(first.value);
    expect(rendered, isNot(contains('/home/person')));
    expect(rendered, isNot(contains('assets/blobs')));
    expect(rendered, isNot(contains('sha256')));
    expect(rendered, isNot(contains(text)));
    expect(
      first.resources.single.role,
      StorageV2AgentToolResultResourceStore.role,
    );
  });

  test('offloads bounded base64 without returning encoded content', () async {
    final bytes = Uint8List.fromList(List<int>.generate(192, (i) => i % 256));
    final encoded = base64.encode(bytes);

    final result = await sanitizer.sanitize({'payload': encoded});
    final rendered = jsonEncode(result.value);

    expect(result.resources, hasLength(1));
    expect(rendered, isNot(contains(encoded)));
    expect(rendered, contains('[binary content omitted]'));
    expect(
      await storage.readResourceBlob(
        (await storage.loadResources()).single.sha256Hash!,
      ),
      bytes,
    );
  });

  test('omits base64 candidates beyond the bounded detection window', () async {
    final bounded = AgentToolResultSanitizer.storageV2(
      storage,
      limits: const AgentToolResultSanitizerLimits(
        maxInlineBytes: 512,
        maxOffloadBytes: 4096,
        binaryDetectionBytes: 128,
      ),
    );
    final encoded = base64.encode(Uint8List(192));

    final result = await bounded.sanitize(encoded);

    expect(result.resources, isEmpty);
    expect(result.value, '[OMITTED: base64 candidate exceeds detection limit]');
    expect(jsonEncode(result.value), isNot(contains(encoded)));
  });

  test('cancellation after storage rolls back new resource and blob', () async {
    final source = AgentCancellationSource();
    final store = _CancellingStore(
      StorageV2AgentToolResultResourceStore(storage),
      source,
    );
    final cancellingSanitizer = AgentToolResultSanitizer(
      resourceStore: store,
      limits: const AgentToolResultSanitizerLimits(
        maxInlineBytes: 16,
        maxOffloadBytes: 4096,
      ),
    );

    await expectLater(
      cancellingSanitizer.sanitize('x' * 200, cancellationToken: source.token),
      throwsA(isA<AgentCancellationException>()),
    );

    expect(await storage.loadResources(), isEmpty);
    final blobRoot = Directory('${root.path}/storage_v2/assets/blobs');
    final blobs = await blobRoot.exists()
        ? await blobRoot
              .list(recursive: true)
              .where((item) => item is File)
              .toList()
        : const <FileSystemEntity>[];
    expect(blobs, isEmpty);
  });

  test('local-only result is excluded from sync outbox and backup', () async {
    const scope = 'server|agent-result-test';
    await storage.activateSyncScope(scope, deviceId: 'device-1');
    final result = await sanitizer.sanitize('private ${'z' * 1000}');
    final resourceId = result.resources.single.id;

    final outbox = await (await storage.storageDatabase()).loadSyncOutbox(
      scope,
    );
    expect(outbox.where((entry) => entry.recordId == resourceId), isEmpty);

    final backup = await BackupService(
      settingsProvider: SettingsProvider(storageV2: storage),
      modelConfigProvider: ModelConfigProvider(storageV2: storage),
      conversationProvider: ConversationProvider(storageV2: storage),
      featureProvider: FeatureProvider(storageV2: storage),
      roleplayProvider: RoleplayProvider(storageV2: storage),
      storageV2: storage,
      appVersionLoader: () async => 'test',
    ).exportZipBytes(BackupSelection.all());
    final archive = ZipDecoder().decodeBytes(backup);
    final names = archive.files.map((file) => file.name).toList();
    final content = archive.files
        .where((file) => file.isFile)
        .map((file) => file.content as List<int>)
        .expand((bytes) => bytes)
        .toList();

    expect(names, isNot(contains('resources.json')));
    expect(
      utf8.decode(content, allowMalformed: true),
      isNot(contains(resourceId)),
    );
  });
}

class _CancellingStore implements AgentToolResultResourceStore {
  final AgentToolResultResourceStore delegate;
  final AgentCancellationSource source;

  const _CancellingStore(this.delegate, this.source);

  @override
  Future<AgentToolResultStoredResource> store({
    required Uint8List bytes,
    required String mimeType,
    required String name,
  }) async {
    final result = await delegate.store(
      bytes: bytes,
      mimeType: mimeType,
      name: name,
    );
    source.cancel();
    return result;
  }

  @override
  Future<void> discard(AgentToolResultStoredResource stored) {
    return delegate.discard(stored);
  }
}
