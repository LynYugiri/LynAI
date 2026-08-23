import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/services/on_device_llm_service.dart';

import '../support/fake_on_device_llm_backend.dart';

void main() {
  late FakeOnDeviceLlmBackend backend;
  late OnDeviceLlmService service;

  setUp(() {
    backend = FakeOnDeviceLlmBackend();
    service = OnDeviceLlmService(backend: backend);
  });

  tearDown(() {
    service.dispose();
  });

  test('refreshStatus applies state and notifies listeners', () async {
    backend.status = FakeOnDeviceLlmBackend.validatedStatus;
    var notified = 0;
    service.addListener(() => notified++);

    final status = await service.refreshStatus();

    expect(status.state, LocalLlmState.validated);
    expect(status.isVisibleToUser, isTrue);
    expect(notified, 1);
  });

  test(
    'ensureReady uses Demo defaults when model config has no overrides',
    () async {
      backend.status = FakeOnDeviceLlmBackend.validatedStatus;

      await service.ensureReady(ModelConfig.localBlueLm());

      final init = backend.calls.firstWhere((call) => call.method == 'init');
      final params = init.arguments['params'] as Map<String, dynamic>;
      expect(params['nPredict'], 200);
      expect(params['nCtx'], 4096);
      expect(params['nThreads'], 4);
      expect(params['topK'], 1);
      expect(params['topP'], 1.0);
      expect(params['temperature'], 0.0);
      expect(params['npuPower'], 100);
      expect(params['multimodal'], isFalse);
      expect(service.status.isReady, isTrue);
    },
  );

  test('ensureReady fails fast for permission required', () async {
    backend.status = FakeOnDeviceLlmBackend.statusWith('permission_required');

    final raw = await backend.invoke('refreshStatus');
    expect(raw['state'], 'permission_required');
    expect(
      LocalLlmStatus.fromJson(raw).state,
      LocalLlmState.permissionRequired,
    );
    final refreshed = await service.refreshStatus();
    expect(refreshed.state, LocalLlmState.permissionRequired);
    await expectLater(
      service.ensureReady(ModelConfig.localBlueLm()),
      throwsA(
        isA<LocalLlmException>().having(
          (error) => error.code,
          'code',
          'permission_required',
        ),
      ),
    );
    expect(backend.calls.any((call) => call.method == 'init'), isFalse);
  });

  test(
    'generate streams token, completed and serializes generations',
    () async {
      backend.status = FakeOnDeviceLlmBackend.readyStatus;
      final config = ModelConfig.localBlueLm();

      final deltasFuture = service.generate(config, '你好').toList();
      await pumpEventQueue();
      final generate = backend.calls.firstWhere(
        (call) => call.method == 'generate',
      );
      final requestId = generate.arguments['requestId'] as String;
      backend.emit({'type': 'token', 'requestId': requestId, 'token': '你'});
      backend.emit({'type': 'token', 'requestId': requestId, 'token': '好'});
      backend.emit({'type': 'completed', 'requestId': requestId});
      final deltas = await deltasFuture;

      expect(
        deltas
            .where((delta) => delta.token != null)
            .map((delta) => delta.token),
        ['你', '好'],
      );
      expect(deltas.last.completed, isTrue);
      expect(generate.arguments['prompt'], '你好');
    },
  );

  test('generate rejects concurrent generation', () async {
    backend.status = FakeOnDeviceLlmBackend.readyStatus;
    final config = ModelConfig.localBlueLm();
    final first = service
        .generate(config, 'first')
        .listen((_) {}, onError: (Object _) {});
    await pumpEventQueue();
    expect(backend.calls.any((call) => call.method == 'generate'), isTrue);
    expect(service.hasActiveGeneration, isTrue);

    Object? caught;
    try {
      await service.generate(config, 'second').toList();
    } catch (error) {
      caught = error;
    }
    expect(caught, isA<LocalLlmException>());
    expect((caught as LocalLlmException).code, 'busy');

    await first.cancel();
    await pumpEventQueue();
  });

  test('maps SDK context overflow error to LocalLlmException', () async {
    backend.status = FakeOnDeviceLlmBackend.readyStatus;
    final chunksFuture = service
        .generate(ModelConfig.localBlueLm(), 'long prompt')
        .toList();
    await pumpEventQueue();
    final generate = backend.calls.firstWhere(
      (call) => call.method == 'generate',
    );
    final requestId = generate.arguments['requestId'] as String;
    backend.emit({
      'type': 'error',
      'requestId': requestId,
      'code': -3070,
      'message': 'prompt too long',
    });

    await expectLater(
      chunksFuture,
      throwsA(
        isA<LocalLlmException>()
            .having((error) => error.code, 'code', '-3070')
            .having((error) => error.isContextOverflow, 'overflow', isTrue),
      ),
    );
  });

  test('visible states cover validated, initializing and ready only', () {
    expect(
      LocalLlmStatus(state: LocalLlmState.validated).isVisibleToUser,
      isTrue,
    );
    expect(
      LocalLlmStatus(state: LocalLlmState.initializing).isVisibleToUser,
      isTrue,
    );
    expect(LocalLlmStatus(state: LocalLlmState.ready).isVisibleToUser, isTrue);
    for (final state in [
      LocalLlmState.notConfigured,
      LocalLlmState.permissionRequired,
      LocalLlmState.modelNotFound,
      LocalLlmState.invalidModel,
      LocalLlmState.error,
      LocalLlmState.unsupported,
      LocalLlmState.unknown,
    ]) {
      expect(LocalLlmStatus(state: state).isVisibleToUser, isFalse);
    }
  });
}
