import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_persistence.dart';
import 'package:lynai/pages/mcp_settings_page.dart';
import 'package:lynai/providers/mcp_provider.dart';
import 'package:lynai/repositories/mcp_repository.dart';
import 'package:lynai/services/agent_tool_registry.dart';
import 'package:lynai/services/mcp/mcp_client.dart';
import 'package:lynai/services/mcp/mcp_connection_factory.dart';
import 'package:provider/provider.dart';

void main() {
  testWidgets('shows server status and gates stdio on unsupported platforms', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 27);
    final provider = McpProvider(
      repository: _WidgetRepository(
        AgentMcpServerRecord(
          id: 'remote',
          name: 'Remote tools',
          transport: 'http',
          url: 'https://mcp.example.test',
          enabled: false,
          createdAt: now,
          updatedAt: now,
        ),
      ),
      connectionFactory: const _UnsupportedFactory(),
      toolRegistry: AgentToolRegistry(),
    );
    await provider.load();

    await tester.pumpWidget(
      ChangeNotifierProvider.value(
        value: provider,
        child: const MaterialApp(home: McpSettingsPage()),
      ),
    );
    expect(find.text('Remote tools'), findsOneWidget);
    expect(find.textContaining('未连接'), findsOneWidget);

    await tester.tap(find.text('添加服务'));
    await tester.pumpAndSettle();
    expect(find.text('stdio 仅支持 Linux、macOS 和 Windows'), findsOneWidget);
    final segmentedButton = tester.widget<SegmentedButton<String>>(
      find.byType(SegmentedButton<String>),
    );
    expect(
      segmentedButton.segments
          .singleWhere((item) => item.value == 'stdio')
          .enabled,
      isFalse,
    );
  });
}

class _WidgetRepository implements McpRepository {
  _WidgetRepository(this.server);

  AgentMcpServerRecord server;

  @override
  Future<List<AgentMcpServerRecord>> loadServers() async => [server];

  @override
  Future<void> saveServer(AgentMcpServerRecord value) async => server = value;

  @override
  Future<McpServerPreferences> loadPreferences(String serverId) async =>
      const McpServerPreferences();

  @override
  Future<void> savePreferences(
    String serverId,
    McpServerPreferences preferences,
  ) async {}

  @override
  Future<Map<String, String>> loadCredentials(
    String serverId,
    Iterable<String> names,
  ) async => const {};

  @override
  Future<void> saveCredentials(
    String serverId,
    Map<String, String> values,
    Iterable<String> removedNames,
  ) async {}
}

class _UnsupportedFactory implements McpConnectionFactory {
  const _UnsupportedFactory();

  @override
  bool get supportsStdio => false;

  @override
  Future<McpClient> create(
    AgentMcpServerRecord server,
    McpServerPreferences preferences,
    Map<String, String> credentials,
  ) => throw UnimplementedError();
}
