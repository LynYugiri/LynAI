import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/services/floating_assistant_service.dart';
import 'package:lynai/services/floating_chat_session_controller.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repositories.dart';

FloatingChatSessionController _buildController(SettingsProvider settings) {
  return FloatingChatSessionController(
    settings: settings,
    conversations: memoryConversationProvider(),
    models: memoryModelConfigProvider(),
    features: FeatureProvider(),
    plugins: PluginProvider(),
  );
}

SettingsProvider _memorySettingsProvider() => memorySettingsProvider();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('blockId', () {
    test('is stable for identical text + bounds', () {
      final a = FloatingChatSessionController.blockIdForTest('Hi', 1, 2, 3, 4);
      final b = FloatingChatSessionController.blockIdForTest('Hi', 1, 2, 3, 4);
      expect(a, b);
    });

    test('differs when text or bounds change meaningfully', () {
      // G2: ~8px tolerance keeps the id stable across minor jitter but changes
      // it for blocks at a clearly different position.
      final a = FloatingChatSessionController.blockIdForTest('Hi', 1, 2, 3, 4);
      // Far-away bounds should not collide.
      expect(
        a,
        isNot(FloatingChatSessionController.blockIdForTest('Hi', 1, 2, 3, 200)),
      );
      // Different text should not collide.
      expect(
        a,
        isNot(FloatingChatSessionController.blockIdForTest('Hi!', 1, 2, 3, 4)),
      );
    });

    test('tolerates sub-8px bounds drift', () {
      // G2: blocks within the same 8px bucket share an id so minor scroll/jitter
      // reuses the cache instead of re-translating identical content.
      final a = FloatingChatSessionController.blockIdForTest('Hi', 1, 2, 3, 4);
      final b = FloatingChatSessionController.blockIdForTest('Hi', 1, 2, 3, 5);
      expect(a, b);
    });
  });

  group('buildTranslationPrompt', () {
    test('mentions target language and JSON format', () {
      final prompt = FloatingChatSessionController.buildTranslationPrompt(
        '简体中文',
        '',
      );
      expect(prompt, contains('简体中文'));
      expect(prompt, contains('JSON'));
      expect(prompt, contains('"index"'));
      expect(prompt, contains('"translation"'));
    });

    test('includes package hint when provided', () {
      final prompt = FloatingChatSessionController.buildTranslationPrompt(
        'English',
        'com.example.app',
      );
      expect(prompt, contains('com.example.app'));
    });
  });

  group('isLikelyUiLabel', () {
    late FloatingChatSessionController controller;
    setUp(() {
      controller = _buildController(_memorySettingsProvider());
    });
    tearDown(() => controller.dispose());

    test('drops single ASCII characters', () {
      expect(controller.isLikelyUiLabel('A'), isTrue);
    });

    test('keeps CJK single character for manga context', () {
      expect(controller.isLikelyUiLabel('啊'), isFalse);
    });

    test('keeps meaningful short Latin words', () {
      expect(controller.isLikelyUiLabel('Yes'), isFalse);
      expect(controller.isLikelyUiLabel('OK'), isTrue);
    });

    test('keeps CJK double char tokens', () {
      expect(controller.isLikelyUiLabel('你好'), isFalse);
    });
  });

  group('parseTranslations', () {
    late FloatingChatSessionController controller;
    setUp(() {
      controller = _buildController(_memorySettingsProvider());
    });
    tearDown(() => controller.dispose());

    List<Map<String, dynamic>> blocksFor(int count) {
      return List.generate(count, (i) {
        return <String, dynamic>{
          'id': FloatingChatSessionController.blockIdForTest(
            't$i',
            0,
            i,
            10,
            i + 1,
          ),
          'originalText': 't$i',
        };
      });
    }

    test('parses raw JSON array', () {
      final blocks = blocksFor(2);
      final result = controller.parseTranslations(
        '[{"index":0,"translation":"你好"},{"index":1,"translation":"世界"}]',
        blocks,
      );
      expect(result[blocks[0]['id']], '你好');
      expect(result[blocks[1]['id']], '世界');
    });

    test('parses fenced ```json output', () {
      final blocks = blocksFor(1);
      final result = controller.parseTranslations(
        '```json\n[{"index":0,"translation":"x"}]\n```',
        blocks,
      );
      expect(result[blocks[0]['id']], 'x');
    });

    test('ignores out-of-range indices', () {
      final blocks = blocksFor(1);
      final result = controller.parseTranslations(
        '[{"index":5,"translation":"nope"}]',
        blocks,
      );
      expect(result, isEmpty);
    });

    test('skips empty translations', () {
      final blocks = blocksFor(2);
      final result = controller.parseTranslations(
        '[{"index":0,"translation":""},{"index":1,"translation":"y"}]',
        blocks,
      );
      expect(result.length, 1);
      expect(result[blocks[1]['id']], 'y');
    });

    test('falls back to line-per-block for plain text', () {
      final blocks = blocksFor(2);
      final result = controller.parseTranslations('[0] 你好\n[1] 世界', blocks);
      expect(result[blocks[0]['id']], '你好');
      expect(result[blocks[1]['id']], '世界');
    });
  });

  group('translation model fallback', () {
    test('disabled screen context blocks the tool', () async {
      final settings = _memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(
          floatingAssistant: const FloatingAssistantSettings(
            allowScreenContext: true,
            screenContextMode: FloatingAssistantSettings.screenContextDisabled,
          ),
        ),
      );
      final controller = _buildController(settings);
      try {
        expect(controller.screenContextToolAllowed, isFalse);
      } finally {
        await controller.dispose();
      }
    });

    test('manual mode allows the screen context tool', () async {
      final settings = _memorySettingsProvider();
      await settings.replaceSettings(
        AppSettings.defaults().copyWith(
          floatingAssistant: const FloatingAssistantSettings(
            allowScreenContext: true,
            screenContextMode: FloatingAssistantSettings.screenContextManual,
          ),
        ),
      );
      final controller = _buildController(settings);
      try {
        expect(controller.screenContextToolAllowed, isTrue);
      } finally {
        await controller.dispose();
      }
    });
  });

  // F1: stopTranslation should be a no-op when nothing is active and must not
  // throw on the platform bridge; clearTranslation likewise serves as the
  // "tear the session down" exit. The settle mutex starts released.
  group('translation session lifecycle', () {
    test('stopTranslation is a no-op when idle', () async {
      final controller = _buildController(_memorySettingsProvider());
      try {
        await controller.stopTranslation();
        expect(controller.isTranslationStreaming, isFalse);
      } finally {
        await controller.dispose();
      }
    });

    test('clearTranslation is a no-op when idle', () async {
      final controller = _buildController(_memorySettingsProvider());
      try {
        controller.clearTranslation();
        expect(controller.isTranslationStreaming, isFalse);
      } finally {
        await controller.dispose();
      }
    });

    test('onTranslationScrollSettled is a no-op when inactive', () async {
      final controller = _buildController(_memorySettingsProvider());
      try {
        // Guard at top must short-circuit before any OCR/network call.
        await controller.onTranslationScrollSettled();
        expect(controller.isTranslationStreaming, isFalse);
      } finally {
        await controller.dispose();
      }
    });
  });

  test('floating assistant dispose cancels pending position persist', () {
    final service = FloatingAssistantService.instance;
    service.persistPositionForTest(bubbleX: 10, bubbleY: 20);
    expect(service.hasPendingPositionPersistForTest, isTrue);

    service.dispose();

    expect(service.hasPendingPositionPersistForTest, isFalse);
  });

  group('normalizeOcrBlock', () {
    test('forwards new size/angle fields from native OCR', () {
      final raw = <String, dynamic>{
        'text': 'こんにちは',
        'bounds': {'left': 100, 'top': 200, 'right': 240, 'bottom': 232},
        'orientation': 1,
        'boxW': 30,
        'boxH': 320,
        'fontSize': 28,
        'angle': 89,
        'prob': 0.93,
      };
      final normalized = FloatingChatSessionController.normalizeOcrBlock(
        raw,
        'com.example.manga',
      );
      expect(normalized['originalText'], 'こんにちは');
      expect((normalized['bounds'] as Map)['left'], 100);
      expect((normalized['bounds'] as Map)['bottom'], 232);
      expect(normalized['orientation'], 1);
      expect(normalized['boxW'], 30);
      expect(normalized['boxH'], 320);
      expect(normalized['fontSize'], 28);
      expect(normalized['angle'], 89);
      expect(normalized['packageName'], 'com.example.manga');
    });

    test('id is stable and does not depend on the new fields', () {
      final raw = <String, dynamic>{
        'text': 'Hi',
        'bounds': {'left': 100, 'top': 200, 'right': 240, 'bottom': 232},
        'fontSize': 99,
        'boxW': 99,
        'boxH': 99,
        'angle': 99,
      };
      final a = FloatingChatSessionController.normalizeOcrBlock(raw, 'pkg.a');
      final b = FloatingChatSessionController.normalizeOcrBlock(
        <String, dynamic>{
          'text': 'Hi',
          'bounds': {'left': 100, 'top': 200, 'right': 240, 'bottom': 232},
        },
        'pkg.b',
      );
      expect(a['id'], b['id']);
      expect(
        a['id'],
        FloatingChatSessionController.blockIdForTest('Hi', 100, 200, 240, 232),
      );
    });

    test('missing size fields default to 0, not null', () {
      final normalized = FloatingChatSessionController.normalizeOcrBlock(
        <String, dynamic>{
          'text': 'x',
          'bounds': {'left': 0, 'top': 0, 'right': 10, 'bottom': 10},
        },
        '',
      );
      expect(normalized['boxW'], 0);
      expect(normalized['boxH'], 0);
      expect(normalized['fontSize'], 0);
      expect(normalized['angle'], 0);
      expect(normalized['orientation'], 0);
    });

    test('tolerates bounds as double-typed numbers', () {
      final normalized = FloatingChatSessionController.normalizeOcrBlock(
        <String, dynamic>{
          'text': 'x',
          'bounds': {'left': 10.0, 'top': 20.5, 'right': 30.4, 'bottom': 40.9},
          'fontSize': 16.0,
        },
        '',
      );
      expect((normalized['bounds'] as Map)['top'], 20);
      expect((normalized['bounds'] as Map)['right'], 30);
      expect(normalized['fontSize'], 16);
    });
  });
}
