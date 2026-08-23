import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/community.dart';
import 'package:lynai/models/plugin_market_entry.dart';
import 'package:lynai/pages/community_post_editor_page.dart';
import 'package:lynai/services/community_service.dart';
import 'package:lynai/services/market_service.dart';

void main() {
  testWidgets('editor can attach an approved plugin and submits its id', (
    tester,
  ) async {
    final community = _FakeCommunityService();
    final market = _FakeMarketService();

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: FilledButton(
                onPressed: () async {
                  await Navigator.push<CommunityPost>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommunityPostEditorPage(
                        service: community,
                        marketService: market,
                      ),
                    ),
                  );
                },
                child: const Text('打开编辑器'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('打开编辑器'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('分享插件'));
    await tester.pumpAndSettle();

    expect(find.text('Pickable Plugin'), findsOneWidget);
    await tester.tap(find.text('Pickable Plugin'));
    await tester.pumpAndSettle();

    expect(find.text('Pickable Plugin'), findsOneWidget);
    expect(find.text('更换'), findsOneWidget);

    await tester.tap(find.text('发布'));
    await tester.pumpAndSettle();

    expect(community.lastPluginId, 'pickable-plugin');
    expect(find.text('打开编辑器'), findsOneWidget);
  });
}

class _FakeCommunityService implements CommunityService {
  String? lastPluginId;

  @override
  bool get isBackendConnected => true;

  @override
  Future<CommunityPost> createPost({
    required String title,
    required String content,
    List<String> mediaIds = const [],
    String? pluginId,
  }) async {
    lastPluginId = pluginId;
    return CommunityPost(
      id: 'p1',
      author: const CommunityUser(id: 'u1', displayName: 'User'),
      content: content,
      createdAt: DateTime(2026, 7, 18),
    );
  }

  @override
  String mediaUrl(String id) => 'https://example.test/community/media/$id';

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMarketService implements MarketService {
  @override
  bool get isBackendConnected => true;

  @override
  Future<MarketQueryResult> listPlugins(MarketQuery query) async {
    return MarketQueryResult(
      entries: [
        MarketPluginEntry(
          id: 'pickable-plugin',
          name: 'Pickable Plugin',
          author: 'Author',
          uploaderName: 'Uploader',
          description: 'A plugin to share',
          version: '2.0.0',
          downloadUrl: '/market/plugins/pickable-plugin/download',
        ),
      ],
      hasMore: false,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
