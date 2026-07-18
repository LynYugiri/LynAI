import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/community.dart';
import 'package:lynai/pages/community_page.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/services/account_service.dart';
import 'package:lynai/services/community_service.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('feed loads only after the community tab becomes active', (
    tester,
  ) async {
    final service = _FakeCommunityService();
    final account = AccountProvider(service: _FakeAccountService());
    addTearDown(account.dispose);

    Widget build(bool active) => ChangeNotifierProvider<AccountProvider>.value(
      value: account,
      child: MaterialApp(
        home: CommunityPage(
          active: active,
          onOpenSettings: () {},
          communityService: service,
        ),
      ),
    );

    await tester.pumpWidget(build(false));
    await tester.pump();
    expect(service.listCalls, 0);

    await tester.pumpWidget(build(true));
    await tester.pump();
    await tester.pump();

    expect(service.listCalls, 1);
    expect(find.text('First community post'), findsOneWidget);
  });
}

class _FakeCommunityService implements CommunityService {
  int listCalls = 0;

  @override
  bool get isBackendConnected => true;

  @override
  Future<CommunityPageResult<CommunityPost>> listPosts({
    int page = 1,
    int pageSize = 20,
  }) async {
    listCalls++;
    return CommunityPageResult(
      items: [
        CommunityPost(
          id: 'p1',
          author: const CommunityUser(id: 'u1', displayName: 'User'),
          content: 'First community post',
          createdAt: DateTime(2026, 7, 18),
        ),
      ],
      hasMore: false,
    );
  }

  @override
  String mediaUrl(String id) => 'https://example.test/community/media/$id';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeAccountService implements AccountService {
  @override
  bool get isBackendConnected => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
