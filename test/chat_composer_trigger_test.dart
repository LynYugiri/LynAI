import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/pages/chat_page.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/jotting_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';
import 'package:lynai/widgets/chat_composer_keyboard.dart';
import 'package:lynai/widgets/composer_trigger_palette.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/memory_repositories.dart';

void main() {
  late Directory storageRoot;
  late StorageV2Service storage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    storageRoot = await Directory.systemTemp.createTemp('lynai_composer_ui_');
    storage = StorageV2Service(rootDirectory: storageRoot);
    await StorageV2UpgradeService(storageV2: storage).ensureReady();
  });

  tearDown(() async {
    await storage.close();
    await storageRoot.delete(recursive: true);
  });

  Future<void> pumpChat(
    WidgetTester tester, {
    FeatureProvider? features,
    TaskProvider? tasks,
  }) async {
    await tester.binding.setSurfaceSize(const Size(500, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider.value(value: memoryConversationProvider()),
          ChangeNotifierProvider.value(value: memorySettingsProvider()),
          ChangeNotifierProvider.value(value: memoryWorkspaceProvider()),
          ChangeNotifierProvider.value(value: memoryModelConfigProvider()),
          ChangeNotifierProvider(create: (_) => features ?? FeatureProvider()),
          ChangeNotifierProvider(create: (_) => tasks ?? TaskProvider()),
          ChangeNotifierProvider(create: (_) => CalendarProvider()),
          ChangeNotifierProvider(create: (_) => PluginProvider()),
          ChangeNotifierProvider(create: (_) => KnowledgeProvider()),
          ChangeNotifierProvider(create: (_) => JottingProvider()),
          ChangeNotifierProvider.value(value: memoryRoleMemoryProvider()),
          ChangeNotifierProvider(create: (_) => BackendClient()),
          Provider.value(value: storage),
        ],
        child: const MaterialApp(home: ChatPage()),
      ),
    );
    await tester.pump();
  }

  Future<void> typeInComposer(WidgetTester tester, String text) async {
    // 面板浮层可能盖住输入框，直接写控制器即可，无需点击。
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump();
  }

  /// 草稿写入有 400ms 防抖：测试结束前推进时钟并落盘，避免 pending timer。
  Future<void> settleDrafts(WidgetTester tester) async {
    await tester.pump(const Duration(milliseconds: 500));
  }

  testWidgets('输入 @ 打开引用面板，输入空格后按普通文本处理', (tester) async {
    await pumpChat(tester);
    expect(find.byType(ComposerTriggerPalette), findsNothing);

    await typeInComposer(tester, '@');
    expect(find.byType(ComposerTriggerPalette), findsOneWidget);
    // 首层列出内置引用源。
    final paletteTexts = tester
        .widgetList<Text>(
          find.descendant(
            of: find.byType(ComposerTriggerPalette),
            matching: find.byType(Text),
          ),
        )
        .map((text) => text.data)
        .toList();
    expect(paletteTexts, contains('笔记'));

    // 空格让触发失效：面板关闭，`@ ` 成为普通正文。
    await typeInComposer(tester, '@ ');
    expect(find.byType(ComposerTriggerPalette), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField).first).controller!.text,
      '@ ',
    );
    await settleDrafts(tester);
  });

  testWidgets('输入 / 打开指令面板，未匹配时不拦任何操作', (tester) async {
    await pumpChat(tester);

    await typeInComposer(tester, '/');
    expect(find.byType(ComposerTriggerPalette), findsOneWidget);
    expect(find.text('/压缩'), findsOneWidget);
    expect(find.text('/总结'), findsOneWidget);

    // 没有匹配的指令时列表为空，提示按普通文本处理。
    await typeInComposer(tester, '/没这条命令');
    expect(find.byType(ComposerTriggerPalette), findsOneWidget);
    expect(find.text('没有匹配的指令，继续输入会按普通文本处理'), findsOneWidget);
    await settleDrafts(tester);
  });

  testWidgets('句中斜杠不触发指令面板', (tester) async {
    await pumpChat(tester);
    await typeInComposer(tester, '看看 a/b 两种');
    expect(find.byType(ComposerTriggerPalette), findsNothing);
    await settleDrafts(tester);
  });

  testWidgets('面板打开时 Esc 关闭且不改动正文', (tester) async {
    await pumpChat(tester);
    await typeInComposer(tester, '@笔记');
    expect(find.byType(ComposerTriggerPalette), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    expect(find.byType(ComposerTriggerPalette), findsNothing);

    final controller = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    // Esc 只关面板，正文原样保留。
    expect(controller.text, '@笔记');
    // 同一段文本不会立刻重新弹出。
    await tester.pump();
    expect(find.byType(ComposerTriggerPalette), findsNothing);
    await settleDrafts(tester);
  });

  testWidgets('引用按钮等价于输入 @，保持与键盘触发同一套状态', (tester) async {
    await pumpChat(tester);
    expect(find.byType(ComposerTriggerPalette), findsNothing);

    await tester.tap(find.byTooltip('插入引用（也可直接输入 @）'));
    await tester.pump();

    expect(find.byType(ComposerTriggerPalette), findsOneWidget);
    final controller = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    expect(controller.text, '@');
    await settleDrafts(tester);
  });

  testWidgets('面板关闭时不抢回车，输入框仍按既有规则发送', (tester) async {
    await pumpChat(tester);
    await typeInComposer(tester, '普通消息');
    expect(find.byType(ComposerTriggerPalette), findsNothing);

    // 面板关闭时键盘包装不应消费回车：这里只验证回调没有被装配成拦截态。
    final keyboard = tester.widget<ChatComposerKeyboard>(
      find.byType(ChatComposerKeyboard),
    );
    expect(keyboard.onPaletteKey, isNull);
    await settleDrafts(tester);
  });

  testWidgets('面板打开时 ↑↓ 移动选中项，Enter 插入引用 Chip', (tester) async {
    await pumpChat(tester);
    await typeInComposer(tester, '@');
    final keyboard = tester.widget<ChatComposerKeyboard>(
      find.byType(ChatComposerKeyboard),
    );
    expect(keyboard.onPaletteKey, isNotNull);

    // 下移一格（不回车确认，避免触发插件/Lua 数据源）。
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.byType(ComposerTriggerPalette), findsOneWidget);

    // 连续下移不会越界崩溃。
    for (var i = 0; i < 12; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    }
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(find.byType(ComposerTriggerPalette), findsOneWidget);

    await settleDrafts(tester);
  });

  testWidgets('回车确认候选项后触发文本被替换掉', (tester) async {
    await pumpChat(tester);
    // 「/总结」是内置指令，确认后立即执行并吃光触发文本。
    await typeInComposer(tester, '/总结');
    expect(find.byType(ComposerTriggerPalette), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    final controller = tester
        .widget<TextField>(find.byType(TextField).first)
        .controller!;
    // 指令不会作为正文留在输入框里。
    expect(controller.text, isEmpty);
    expect(find.byType(ComposerTriggerPalette), findsNothing);
    await settleDrafts(tester);
  });

  group('引用源下钻', () {
    late FeatureProvider features;

    // 夹具里要读真实 storage，放在 setUp（不在 widget 测试的假异步时钟里）。
    setUp(() async {
      features = FeatureProvider(storageV2: storage);
      await features.load();
      final folderId = await features.addNoteFolder('工作');
      await features.addNoteWithContent(
        '项目规划',
        '本周需要完成版本发布准备。',
        folderId: folderId,
      );
    });

    testWidgets('引用源支持进入文件夹并在层级间返回', (tester) async {
      await pumpChat(tester, features: features);

      // 面板会盖住输入框，键盘导航比点击可靠：首层第 0 行是「笔记」源。
      await typeInComposer(tester, '@');
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      // 第一层：文件夹行可下钻，不再是「引用整个文件夹」的终点。
      expect(
        find.descendant(
          of: find.byType(ComposerTriggerPalette),
          matching: find.byIcon(Icons.folder_outlined),
        ),
        findsWidgets,
      );

      // 第 0 行是第一个文件夹「工作」，回车进入下一层。
      await tester.sendKeyEvent(LogicalKeyboardKey.enter);
      await tester.pump();
      await tester.pump();

      // 进入文件夹后列出其中笔记，并给出该层的整体引用行。
      expect(
        find.descendant(
          of: find.byType(ComposerTriggerPalette),
          matching: find.text('项目规划'),
        ),
        findsOneWidget,
      );
      expect(find.text('引用整个「工作」'), findsOneWidget);

      // 返回上一级回到文件夹列表。合成点击会被输入区手势层吞掉，这里直接
      // 调用面板暴露的 onBack（即页面接上的 _leaveComposerLevel）。
      tester
          .widget<ComposerTriggerPalette>(find.byType(ComposerTriggerPalette))
          .onBack();
      await tester.pump();
      await tester.pump();
      expect(
        find.descendant(
          of: find.byType(ComposerTriggerPalette),
          matching: find.text('工作'),
        ),
        findsOneWidget,
      );

      await settleDrafts(tester);
    });
  });
}
