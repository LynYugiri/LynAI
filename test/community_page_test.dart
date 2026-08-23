import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/community.dart';
import 'package:lynai/pages/community_page.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/services/account_service.dart';
import 'package:lynai/services/backend_client.dart';
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

  testWidgets('shared plugin card opens the plugin market detail page', (
    tester,
  ) async {
    final service = _FakeCommunityService(withPlugin: true);
    final account = AccountProvider(service: _FakeAccountService());
    final backend = BackendClient()..configure('https://example.test');
    addTearDown(account.dispose);
    addTearDown(backend.close);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<AccountProvider>.value(value: account),
          ChangeNotifierProvider<BackendClient>.value(value: backend),
        ],
        child: MaterialApp(
          home: CommunityPage(
            active: true,
            onOpenSettings: () {},
            communityService: service,
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();

    expect(find.text('Shared Plugin'), findsOneWidget);
    await tester.tap(find.text('Shared Plugin'));
    await tester.pumpAndSettle();

    expect(find.text('安装'), findsOneWidget);
  });
}

class _FakeCommunityService implements CommunityService {
  _FakeCommunityService({this.withPlugin = false});

  final bool withPlugin;
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
        if (withPlugin)
          CommunityPost(
            id: 'p2',
            author: const CommunityUser(id: 'u1', displayName: 'User'),
            content: '试试这个插件',
            createdAt: DateTime(2026, 7, 18),
            plugin: const CommunityPluginShare(
              id: 'shared-plugin',
              name: 'Shared Plugin',
              author: 'Author',
              description: 'desc',
              version: '1.0.0',
            ),
          )
        else
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
