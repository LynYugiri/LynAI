import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/model_config.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/api_service.dart';
import 'package:lynai/services/floating_chat_session_controller.dart';
import 'package:lynai/services/floating_translation_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repositories.dart';

const _ocrGroups = <Map<String, dynamic>>[
  {
    'id': 'group-1',
    'packageName': 'com.example.manga',
    'text': 'hello',
    'bounds': {'left': 10, 'top': 20, 'right': 100, 'bottom': 40},
  },
];

ModelConfig _model() => ModelConfig(
  id: 'chat-model',
  name: 'Chat model',
  endpoint: 'https://example.invalid',
  apiKey: '',
  modelName: 'test',
  apiType: 'openai',
  priority: 0,
);

Future<({SettingsProvider settings, ModelConfigProvider models})>
_providers() async {
  final settings = memorySettingsProvider();
  final models = memoryModelConfigProvider();
  await models.replaceModels([_model()]);
  return (settings: settings, models: models);
}

FloatingChatSessionController _chat(SettingsProvider settings) {
  return FloatingChatSessionController(
    settings: settings,
    conversations: memoryConversationProvider(),
    models: memoryModelConfigProvider(),
    features: FeatureProvider(),
    tasks: TaskProvider(),
    calendar: CalendarProvider(),
    plugins: PluginProvider(),
  );
}

Future<void> _flushEvents() async {
  await Future<void>.delayed(Duration.zero);
  await Future<void>.delayed(Duration.zero);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('requestId prevents an older capture from starting a request', () async {
    final providers = await _providers();
    final firstCapture = Completer<List<Map<String, dynamic>>>();
    var captureCount = 0;
    var requestCount = 0;
    final controller = FloatingTranslationController(
      settings: providers.settings,
      models: providers.models,
      captureOcrGroups: () {
        captureCount++;
        return captureCount == 1
            ? firstCapture.future
            : Future.value(_ocrGroups);
      },
      sendStreamRequest: (model, messages) {
        requestCount++;
        return Stream.value(
          const StreamChunk(content: '[{"id":"group-1","translation":"new"}]'),
        );
      },
      replaceTranslations: (_) async {},
      clearTranslations: () async {},
    );
    try {
      final first = controller.translateManually();
      await _flushEvents();
      final firstRequestId = controller.requestId;
      await controller.translateManually();
      firstCapture.complete(_ocrGroups);
      await first;
      await _flushEvents();

      expect(controller.requestId, greaterThan(firstRequestId));
      expect(requestCount, 1);
      expect(controller.translationText, 'new');
    } finally {
      await controller.dispose();
    }
  });

  test('stopping automatic translation keeps rendered translations', () async {
    final providers = await _providers();
    final replaced = <Map<String, dynamic>>[];
    final controller = FloatingTranslationController(
      settings: providers.settings,
      models: providers.models,
      captureOcrGroups: () async => _ocrGroups,
      sendStreamRequest: (model, messages) => Stream.value(
        const StreamChunk(content: '[{"id":"group-1","translation":"你好"}]'),
      ),
      replaceTranslations: (payload) async => replaced.add(payload),
      clearTranslations: () async {},
    );
    try {
      await controller.startAutomatic();
      await _flushEvents();
      expect(controller.translationText, '你好');

      await controller.stopAutomatic();

      expect(controller.isAutomatic, isFalse);
      expect(controller.translationText, '你好');
      expect(controller.translations, isNotEmpty);
      expect(replaced, hasLength(1));
      expect(controller.status, contains('保留当前译文'));
    } finally {
      await controller.dispose();
    }
  });

  test(
    'stopping during an automatic refresh restores the previous scene',
    () async {
      final providers = await _providers();
      final refreshCapture = Completer<List<Map<String, dynamic>>>();
      final replaced = <Map<String, dynamic>>[];
      var captureCount = 0;
      final controller = FloatingTranslationController(
        settings: providers.settings,
        models: providers.models,
        captureOcrGroups: () {
          captureCount++;
          return captureCount == 1
              ? Future.value(_ocrGroups)
              : refreshCapture.future;
        },
        sendStreamRequest: (model, messages) => Stream.value(
          const StreamChunk(content: '[{"id":"group-1","translation":"你好"}]'),
        ),
        replaceTranslations: (payload) async => replaced.add(payload),
        clearTranslations: () async {},
      );
      try {
        await controller.startAutomatic();
        await _flushEvents();
        expect(controller.translationText, '你好');

        await controller.onScrollStarted();
        unawaited(controller.onScrollSettled());
        await _flushEvents();
        await controller.stopAutomatic();

        expect(controller.translationText, '你好');
        expect(replaced, hasLength(2));
        expect(replaced.last['blocks'], isNotEmpty);
        refreshCapture.complete(_ocrGroups);
      } finally {
        await controller.dispose();
      }
    },
  );

  test('failed refresh restores the previous scene', () async {
    final providers = await _providers();
    final replaced = <Map<String, dynamic>>[];
    var captureCount = 0;
    final controller = FloatingTranslationController(
      settings: providers.settings,
      models: providers.models,
      captureOcrGroups: () async {
        captureCount++;
        return captureCount == 1 ? _ocrGroups : const [];
      },
      sendStreamRequest: (model, messages) => Stream.value(
        const StreamChunk(content: '[{"id":"group-1","translation":"你好"}]'),
      ),
      replaceTranslations: (payload) async => replaced.add(payload),
      clearTranslations: () async {},
    );
    try {
      await controller.startAutomatic();
      await _flushEvents();
      await controller.onScrollStarted();
      await controller.onScrollSettled();

      expect(controller.translationText, '你好');
      expect(controller.error, '当前页面没有可读取文本');
      expect(replaced, hasLength(2));
    } finally {
      await controller.dispose();
    }
  });

  test('blocked package groups never reach the model', () async {
    final providers = await _providers();
    final floating = providers.settings.settings.floatingAssistant.copyWith(
      blockedPackages: const ['com.example.manga'],
    );
    providers.settings.updateFloatingAssistant(floating);
    var requestCount = 0;
    final controller = FloatingTranslationController(
      settings: providers.settings,
      models: providers.models,
      captureOcrGroups: () async => _ocrGroups,
      sendStreamRequest: (model, messages) {
        requestCount++;
        return const Stream.empty();
      },
      replaceTranslations: (_) async {},
      clearTranslations: () async {},
    );
    try {
      await controller.translateManually();

      expect(requestCount, 0);
      expect(controller.error, '当前页面没有可读取文本');
    } finally {
      await controller.dispose();
    }
  });

  test(
    'native capture errors are exposed instead of reported as no text',
    () async {
      final providers = await _providers();
      final controller = FloatingTranslationController(
        settings: providers.settings,
        models: providers.models,
        captureOcrGroups: () => Future.error('screenshot unavailable'),
        sendStreamRequest: (model, messages) => const Stream.empty(),
        replaceTranslations: (_) async {},
        clearTranslations: () async {},
      );
      try {
        await controller.translateManually();

        expect(controller.error, contains('screenshot unavailable'));
        expect(controller.error, isNot(contains('没有可读取文本')));
        expect(controller.isTranslating, isFalse);
      } finally {
        await controller.dispose();
      }
    },
  );

  test(
    'overlay display errors complete the translation with an error',
    () async {
      final providers = await _providers();
      final controller = FloatingTranslationController(
        settings: providers.settings,
        models: providers.models,
        captureOcrGroups: () async => _ocrGroups,
        sendStreamRequest: (model, messages) => Stream.value(
          const StreamChunk(content: '[{"id":"group-1","translation":"你好"}]'),
        ),
        replaceTranslations: (_) => Future.error('overlay permission denied'),
        clearTranslations: () async {},
      );
      try {
        await controller.translateManually();
        await _flushEvents();

        expect(controller.error, contains('overlay permission denied'));
        expect(controller.translationText, isEmpty);
        expect(controller.isTranslating, isFalse);
      } finally {
        await controller.dispose();
      }
    },
  );

  test('translation prompt requires plain text output', () {
    final prompt = FloatingTranslationController.buildTranslationPrompt(
      '简体中文',
      'com.example.manga',
    );

    expect(prompt, contains('纯文本'));
    expect(prompt, contains('不要使用 Markdown'));
  });

  test('JSON response maps translations by opaque OCR id', () {
    final blocks = <Map<String, dynamic>>[
      {'id': 'bubble:右-2', 'originalText': 'world'},
      {'id': 'bubble:left/1', 'originalText': 'hello'},
    ];
    final input = FloatingTranslationController.buildTranslationInput(blocks);
    final result = FloatingTranslationController.parseTranslations(
      '[{"id":"bubble:left/1","translation":"你好"},'
      '{"id":"unknown","translation":"ignored"},'
      '{"id":"bubble:右-2","translation":"世界"}]',
      blocks,
    );

    expect(input, contains('bubble:右-2'));
    expect(input, contains('bubble:left/1'));
    expect(result, {'bubble:left/1': '你好', 'bubble:右-2': '世界'});
  });

  test(
    'chat and translation controllers own independent request state',
    () async {
      final providers = await _providers();
      final stream = StreamController<StreamChunk>();
      final translation = FloatingTranslationController(
        settings: providers.settings,
        models: providers.models,
        captureOcrGroups: () async => _ocrGroups,
        sendStreamRequest: (model, messages) => stream.stream,
        replaceTranslations: (_) async {},
        clearTranslations: () async {},
      );
      final chat = _chat(providers.settings);
      try {
        unawaited(translation.startAutomatic());
        await _flushEvents();
        expect(translation.isTranslating, isTrue);

        chat.startNewConversation();

        expect(translation.isTranslating, isTrue);
        expect(chat.stateJson(), isNot(contains('translationText')));
        expect(chat.stateJson(), isNot(contains('translationHistory')));

        await translation.stopAutomatic();
        expect(chat.isStreaming, isFalse);
      } finally {
        await stream.close();
        await translation.dispose();
        await chat.dispose();
      }
    },
  );

  group('OCR normalization', () {
    test('keeps native id and geometry fields', () {
      final normalized = FloatingTranslationController.normalizeOcrBlock(
        <String, dynamic>{
          'id': 'native-id',
          'text': 'こんにちは',
          'bounds': {'left': 100, 'top': 200, 'right': 240, 'bottom': 232},
          'orientation': 1,
          'boxW': 30,
          'boxH': 320,
          'fontSize': 28,
          'angle': 89,
        },
        'com.example.manga',
      );

      expect(normalized?['id'], 'native-id');
      expect(normalized?['originalText'], 'こんにちは');
      expect(normalized?['boxW'], 30);
      expect(normalized?['angle'], 89);
      expect(normalized?['packageName'], 'com.example.manga');
    });

    test('generates a jitter-tolerant id when native id is absent', () {
      final a = FloatingTranslationController.blockId('Hi', 1, 2, 3, 4);
      final b = FloatingTranslationController.blockId('Hi', 1, 2, 3, 5);
      expect(a, b);
    });
  });
}
