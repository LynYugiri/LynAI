import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/pages/chat/withdraw_undo_countdown.dart';

void main() {
  Future<void> pumpCountdown(
    WidgetTester tester, {
    Duration duration = const Duration(seconds: 10),
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: WithdrawUndoCountdown(
              duration: duration,
              label: '已撤回，内容回到输入框',
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('初始显示总秒数并带说明文字', (tester) async {
    await pumpCountdown(tester);

    expect(find.text('10'), findsOneWidget);
    expect(find.text('已撤回，内容回到输入框'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      closeTo(1, 0.001),
    );
  });

  testWidgets('秒数随时间递减且环形进度同步收缩', (tester) async {
    await pumpCountdown(tester);

    await tester.pump(const Duration(seconds: 5));
    expect(find.text('5'), findsOneWidget);
    expect(
      tester
          .widget<CircularProgressIndicator>(
            find.byType(CircularProgressIndicator),
          )
          .value,
      closeTo(0.5, 0.01),
    );

    await tester.pump(const Duration(seconds: 4));
    expect(find.text('1'), findsOneWidget);

    await tester.pump(const Duration(seconds: 1));
    // 结束后停在 1，不显示 0，也不超出总时长。
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('环心数字带无障碍说明', (tester) async {
    final handle = tester.ensureSemantics();
    await pumpCountdown(tester);

    expect(find.bySemanticsLabel('撤销剩余 10 秒'), findsOneWidget);

    handle.dispose();
  });
}
