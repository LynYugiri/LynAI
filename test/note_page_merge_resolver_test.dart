import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/merge_models.dart';
import 'package:lynai/widgets/note_page_merge_resolver.dart';

void main() {
  const session = NotePageMergeSession(
    noteId: 'n',
    pageId: 'p',
    expectedHeadIds: {'local', 'incoming'},
    localHeadId: 'local',
    incomingHeadId: 'incoming',
    baseRevisionId: 'base',
    localContent: 'local body',
    incomingContent: 'incoming body',
    baseContent: 'base body',
    initialResult: 'draft merge',
  );

  testWidgets('shows three sides and editable result on desktop', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1200, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: NotePageMergeResolver(
          session: session,
          onCommit: (_) async => const NotePageMergeCommitResult.staleHeads(),
        ),
      ),
    );

    expect(find.text('共同基线'), findsOneWidget);
    expect(find.text('本地版本'), findsOneWidget);
    expect(find.text('传入版本'), findsOneWidget);
    expect(find.widgetWithText(TextField, 'draft merge'), findsOneWidget);
  });

  testWidgets('mobile commit reports stale heads without closing', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        home: NotePageMergeResolver(
          session: session,
          onCommit: (_) async => const NotePageMergeCommitResult.staleHeads(),
        ),
      ),
    );
    await tester.tap(find.text('提交合并'));
    await tester.pumpAndSettle();

    expect(find.text('分页头已变化，请关闭后重新加载冲突'), findsOneWidget);
    expect(find.byType(NotePageMergeResolver), findsOneWidget);
  });
}
