import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/memory_card.dart';
import 'package:lynai/models/memory_card_deck.dart';
import 'package:lynai/models/memory_card_review_log.dart';
import 'package:lynai/pages/features/memory_cards_page.dart';
import 'package:lynai/providers/memory_card_provider.dart';
import 'package:lynai/repositories/memory_card_repository.dart';
import 'package:provider/provider.dart';

class _FakeMemoryCardRepository extends MemoryCardRepository {
  MemoryCardLoadResult snapshot = const MemoryCardLoadResult(
    decks: [],
    cards: [],
    reviewLogs: [],
  );

  @override
  Future<MemoryCardLoadResult> load() async => snapshot;

  @override
  Future<void> saveChanges({
    Iterable<MemoryCardDeck> upsertDecks = const [],
    Iterable<String> deleteDeckIds = const [],
    Iterable<MemoryCard> upsertCards = const [],
    Iterable<String> deleteCardIds = const [],
    Iterable<MemoryCardReviewLog> upsertReviewLogs = const [],
    Iterable<String> deleteReviewLogIds = const [],
  }) async {}

  @override
  Future<void> replace(MemoryCardLoadResult value) async {
    snapshot = value;
  }
}

void main() {
  testWidgets('牌组显示待复习数量并启用复习按钮', (tester) async {
    final provider = await _provider(
      cards: [
        _card(id: 'due-1', deckId: 'deck', status: MemoryCardStatus.newCard),
      ],
    );
    await _pump(tester, provider);

    expect(find.text('牌组 (1)'), findsOneWidget);
    expect(find.text('待复习 1 张 · 共 1 张'), findsOneWidget);

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.textContaining('开始复习'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNotNull);
    expect(find.text('开始复习 (1)'), findsOneWidget);
  });

  testWidgets('没有到期卡片时复习按钮不可用', (tester) async {
    final provider = await _provider(
      cards: [
        _card(
          id: 'future',
          deckId: 'deck',
          status: MemoryCardStatus.review,
          dueAt: DateTime.now().add(const Duration(days: 3)),
        ),
      ],
    );
    await _pump(tester, provider);

    final button = tester.widget<FilledButton>(
      find.ancestor(
        of: find.textContaining('开始复习'),
        matching: find.byType(FilledButton),
      ),
    );
    expect(button.onPressed, isNull);
    expect(find.text('共 1 张'), findsWidgets);
  });

  testWidgets('过滤无结果时可一键清除筛选', (tester) async {
    final provider = await _provider(
      cards: [
        _card(id: 'card-1', deckId: 'deck', status: MemoryCardStatus.newCard),
      ],
    );
    await _pump(tester, provider);

    await tester.enterText(
      find.widgetWithText(TextField, '搜索正面或反面'),
      '不存在的关键词',
    );
    await tester.pumpAndSettle();

    expect(find.text('没有符合条件的卡片'), findsOneWidget);
    expect(find.text('0 / 共 1 张'), findsOneWidget);

    await tester.tap(find.widgetWithText(FilledButton, '清除筛选'));
    await tester.pumpAndSettle();

    expect(find.text('没有符合条件的卡片'), findsNothing);
    expect(find.text('共 1 张'), findsOneWidget);
  });

  testWidgets('新建卡片缺正面或反面时给出校验提示', (tester) async {
    final provider = await _provider();
    await _pump(tester, provider);

    await tester.tap(find.byTooltip('新建卡片'));
    await tester.pumpAndSettle();

    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入卡片正面'), findsOneWidget);
    expect(find.byType(AlertDialog), findsOneWidget);

    await tester.enterText(
      find.widgetWithText(TextField, '正面（问题/提示）'),
      '问题',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();
    expect(find.text('请输入卡片反面'), findsOneWidget);
    expect(provider.cards, isEmpty);
  });

  testWidgets('牌组没有卡片时展示引导入口', (tester) async {
    final provider = await _provider();
    await _pump(tester, provider);

    expect(find.text('这个牌组还没有卡片'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, '新建卡片'), findsOneWidget);
    expect(find.widgetWithText(FilledButton, 'AI 生成卡片'), findsWidgets);
  });

  testWidgets('牌组设置拒绝非数字上限', (tester) async {
    final provider = await _provider();
    await _pump(tester, provider);

    await tester.tap(find.byTooltip('牌组操作'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('牌组设置'));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.widgetWithText(TextField, '每日新卡上限'),
      'abc',
    );
    await tester.tap(find.widgetWithText(FilledButton, '保存'));
    await tester.pumpAndSettle();

    expect(find.text('每日新卡上限需为 0-9999 的整数'), findsOneWidget);
    expect(find.text('牌组设置'), findsOneWidget);
  });

  testWidgets('窄屏布局不溢出', (tester) async {
    final provider = await _provider(
      cards: [
        _card(id: 'due-1', deckId: 'deck', status: MemoryCardStatus.newCard),
      ],
    );
    await _pump(tester, provider, size: const Size(400, 800));

    expect(tester.takeException(), isNull);
    expect(find.text('开始复习 (1)'), findsOneWidget);
    expect(find.text('正面-due-1'), findsOneWidget);
  });
}

MemoryCard _card({
  required String id,
  required String deckId,
  required MemoryCardStatus status,
  DateTime? dueAt,
  String? hint,
  bool enabled = true,
  int reviewCount = 0,
}) => MemoryCard(
  id: id,
  deckId: deckId,
  front: '正面-$id',
  back: '反面-$id',
  hint: hint,
  sourceKind: MemoryCardSourceKind.manual,
  status: status,
  dueAt: dueAt,
  intervalDays: 0,
  easeFactor: 2.5,
  repetitions: 0,
  lapses: 0,
  remainingSteps: 0,
  reviewCount: reviewCount,
  lastReviewedAt: null,
  enabled: enabled,
  sortOrder: 0,
  createdAt: DateTime(2026, 8, 16),
  updatedAt: DateTime(2026, 8, 16),
);

Future<MemoryCardProvider> _provider({List<MemoryCard> cards = const []}) async {
  final provider = MemoryCardProvider(
    repository: _FakeMemoryCardRepository(),
  );
  // replaceAll 会补上内置默认牌组，避免测试里出现额外牌组。
  await provider.replaceAll(
    decks: const [],
    cards: const [],
    reviewLogs: const [],
  );
  if (cards.isNotEmpty) {
    await provider.addCards([
      for (final card in cards)
        card.copyWith(deckId: MemoryCardProvider.builtInDefaultDeckId),
    ]);
  }
  return provider;
}

Future<void> _pump(
  WidgetTester tester,
  MemoryCardProvider provider, {
  Size size = const Size(1000, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    ChangeNotifierProvider<MemoryCardProvider>.value(
      value: provider,
      child: const MaterialApp(
        home: Scaffold(body: MemoryCardsPage()),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
