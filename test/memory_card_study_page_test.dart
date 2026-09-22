import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/memory_card.dart';
import 'package:lynai/models/memory_card_deck.dart';
import 'package:lynai/models/memory_card_review_log.dart';
import 'package:lynai/pages/features/memory_card_study_page.dart';
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
  testWidgets('可以先查看提示再显示答案', (tester) async {
    final provider = await _provider(
      hint: '先想清楚定义',
    );
    await _pump(tester, provider);

    expect(find.textContaining('提示：'), findsNothing);
    expect(find.text('显示提示 (H)'), findsOneWidget);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    await tester.tap(find.text('显示提示 (H)'));
    await tester.pumpAndSettle();

    expect(find.text('提示：先想清楚定义'), findsOneWidget);
    expect(find.text('显示提示 (H)'), findsNothing);
    // 提示不应提前泄露答案。
    expect(find.text('反面-due-1'), findsNothing);

    await tester.tap(find.text('显示答案'));
    await tester.pumpAndSettle();
    expect(find.text('反面-due-1'), findsWidgets);
    expect(find.text('良好'), findsOneWidget);
  });

  testWidgets('评分后记录已复习数量', (tester) async {
    final provider = await _provider();
    await _pump(tester, provider);

    await tester.tap(find.text('显示答案'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('良好'));
    await tester.pumpAndSettle();

    expect(find.textContaining('已复习 1'), findsWidgets);
  });

  testWidgets('窄屏下不溢出且保留进度', (tester) async {
    final provider = await _provider(hint: '提示内容');
    await _pump(tester, provider, size: const Size(400, 720));

    expect(tester.takeException(), isNull);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);
    expect(find.text('显示提示 (H)'), findsOneWidget);
  });
}

Future<MemoryCardProvider> _provider({String? hint}) async {
  final provider = MemoryCardProvider(
    repository: _FakeMemoryCardRepository(),
  );
  await provider.replaceAll(
    decks: const [],
    cards: const [],
    reviewLogs: const [],
  );
  final now = DateTime(2026, 8, 16);
  await provider.addCards([
    MemoryCard(
      id: 'due-1',
      deckId: MemoryCardProvider.builtInDefaultDeckId,
      front: '正面-due-1',
      back: '反面-due-1',
      hint: hint,
      sourceKind: MemoryCardSourceKind.manual,
      status: MemoryCardStatus.newCard,
      dueAt: null,
      intervalDays: 0,
      easeFactor: 2.5,
      repetitions: 0,
      lapses: 0,
      remainingSteps: 0,
      reviewCount: 0,
      lastReviewedAt: null,
      enabled: true,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    ),
  ]);
  return provider;
}

Future<void> _pump(
  WidgetTester tester,
  MemoryCardProvider provider, {
  Size size = const Size(900, 800),
}) async {
  await tester.binding.setSurfaceSize(size);
  addTearDown(() => tester.binding.setSurfaceSize(null));
  final deck = provider.decks.first;
  final cards = provider.dueCards(deck.id);
  await tester.pumpWidget(
    ChangeNotifierProvider<MemoryCardProvider>.value(
      value: provider,
      child: MaterialApp(
        home: MemoryCardStudyPage(deck: deck, cards: cards),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
