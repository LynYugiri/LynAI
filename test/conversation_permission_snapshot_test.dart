import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/web_search.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';

void main() {
  test('app defaults serialize new-conversation and search policy', () {
    final settings = AppSettings.defaults().copyWith(
      agentEnabledByDefault: true,
      agentGrantedPermissions: const [LynAIPermissions.networkAccess],
      webSearchRoute: WebSearchRoute.client,
      webSearchClientProvider: WebSearchClientProvider.searxng,
      searxngEndpoint: 'https://search.example/search',
      searxngAllowHttp: true,
    );

    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.agentEnabledByDefault, isTrue);
    expect(
      restored.agentGrantedPermissions,
      contains(LynAIPermissions.networkAccess),
    );
    expect(restored.webSearchRoute, WebSearchRoute.client);
    expect(restored.webSearchClientProvider, WebSearchClientProvider.searxng);
    expect(restored.searxngEndpoint, 'https://search.example/search');
    expect(restored.searxngAllowHttp, isTrue);
  });
}
