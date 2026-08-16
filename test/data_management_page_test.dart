import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/anniversary.dart';
import 'package:lynai/models/calendar_event.dart';
import 'package:lynai/models/task.dart';
import 'package:lynai/models/task_list.dart';
import 'package:lynai/models/account.dart';
import 'package:lynai/models/cloud_data.dart';
import 'package:lynai/pages/data_management_page.dart';
import 'package:lynai/providers/account_provider.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/cloud_data_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/memory_card_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/plugin_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/sync_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/repositories/calendar_repository.dart';
import 'package:lynai/repositories/cloud_data_repository.dart';
import 'package:lynai/repositories/task_repository.dart';
import 'package:lynai/services/account_service.dart';
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/cloud_data_service.dart';
import 'package:provider/provider.dart';

import 'support/memory_repositories.dart';

void main() {
  testWidgets('planning selections have Material ink and typed callbacks', (
    tester,
  ) async {
    final now = DateTime(2026, 7, 24, 10);
    final tasks = TaskProvider(
      repository: _MemoryTaskRepository(),
      recycleBinRepository: MemoryRecycleBinRepository(),
    );
    final calendar = CalendarProvider(
      repository: _MemoryCalendarRepository(),
      recycleBinRepository: MemoryRecycleBinRepository(),
    );
    await tasks.replaceAll(
      tasks: [Task(id: 'task', title: '测试任务', createdAt: now, updatedAt: now)],
      lists: const [],
      entries: const [],
    );
    await calendar.replaceAll(
      events: [
        CalendarEvent(
          id: 'event',
          title: '测试事件',
          spec: TimedCalendarEventSpec(
            start: now,
            end: now.add(const Duration(hours: 1)),
          ),
          createdAt: now,
          updatedAt: now,
        ),
      ],
      anniversaries: const [],
    );

    await tester.binding.setSurfaceSize(const Size(600, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AccountProvider(service: _MemoryAccountService()),
          ),
          ChangeNotifierProvider(
            create: (_) => CloudDataProvider(
              backend: BackendClient(),
              repository: _MemoryCloudRepository(),
              service: _MemoryCloudService(),
            ),
          ),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => memorySettingsProvider(),
          ),
          ChangeNotifierProvider<ModelConfigProvider>(
            create: (_) => memoryModelConfigProvider(),
          ),
          ChangeNotifierProvider<ConversationProvider>(
            create: (_) => memoryConversationProvider(),
          ),
          ChangeNotifierProvider(create: (_) => FeatureProvider()),
          ChangeNotifierProvider(create: (_) => KnowledgeProvider()),
          ChangeNotifierProvider(create: (_) => MemoryCardProvider()),
          ChangeNotifierProvider<RoleplayProvider>(
            create: (_) => memoryRoleplayProvider(),
          ),
          ChangeNotifierProvider.value(value: tasks),
          ChangeNotifierProvider.value(value: calendar),
          ChangeNotifierProvider(create: (_) => PluginProvider()),
          ChangeNotifierProvider(create: (_) => SyncProvider()),
        ],
        child: const MaterialApp(home: DataManagementPage()),
      ),
    );
    await tester.pumpAndSettle();

    await _expandAndToggle(tester, section: '任务', item: '测试任务');
    await _expandAndToggle(tester, section: '日历', item: '测试事件');

    expect(tester.takeException(), isNull);
  });

  testWidgets('defaults to local and exposes cloud management segment', (
    tester,
  ) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(
            create: (_) => AccountProvider(service: _MemoryAccountService()),
          ),
          ChangeNotifierProvider(
            create: (_) => CloudDataProvider(
              backend: BackendClient(),
              repository: _MemoryCloudRepository(),
              service: _MemoryCloudService(),
            ),
          ),
          ChangeNotifierProvider<SettingsProvider>(
            create: (_) => memorySettingsProvider(),
          ),
          ChangeNotifierProvider<ModelConfigProvider>(
            create: (_) => memoryModelConfigProvider(),
          ),
          ChangeNotifierProvider<ConversationProvider>(
            create: (_) => memoryConversationProvider(),
          ),
          ChangeNotifierProvider(create: (_) => FeatureProvider()),
          ChangeNotifierProvider(create: (_) => KnowledgeProvider()),
          ChangeNotifierProvider(create: (_) => MemoryCardProvider()),
          ChangeNotifierProvider<RoleplayProvider>(
            create: (_) => memoryRoleplayProvider(),
          ),
          ChangeNotifierProvider(
            create: (_) => TaskProvider(repository: _MemoryTaskRepository()),
          ),
          ChangeNotifierProvider(
            create: (_) =>
                CalendarProvider(repository: _MemoryCalendarRepository()),
          ),
          ChangeNotifierProvider(create: (_) => PluginProvider()),
          ChangeNotifierProvider(create: (_) => SyncProvider()),
        ],
        child: const MaterialApp(home: DataManagementPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(
      find.text(
        '普通备份不包含 API Key。只有启用“加密并包含 API Key”时，密钥才会进入密码加密备份；设备私钥和登录令牌永不备份。',
      ),
      findsOneWidget,
    );
    expect(find.text('云端索引与容量'), findsNothing);

    await tester.tap(find.text('云端'));
    await tester.pumpAndSettle();

    expect(find.text('云端索引与容量'), findsOneWidget);
    expect(find.text('立即双向同步'), findsOneWidget);
    expect(find.text('清空全部云端'), findsOneWidget);
  });
}

Future<void> _expandAndToggle(
  WidgetTester tester, {
  required String section,
  required String item,
}) async {
  final sectionFinder = find.widgetWithText(ExpansionTile, section);
  await tester.scrollUntilVisible(
    sectionFinder,
    300,
    scrollable: find.byType(Scrollable).first,
  );
  await tester.tap(sectionFinder);
  await tester.pumpAndSettle();

  final itemFinder = find.widgetWithText(CheckboxListTile, item);
  await tester.scrollUntilVisible(
    itemFinder,
    200,
    scrollable: find.byType(Scrollable).first,
  );
  expect(
    find.ancestor(of: itemFinder, matching: find.byType(Material)),
    findsWidgets,
  );
  await tester.tap(itemFinder);
  await tester.pumpAndSettle();
}

final class _MemoryTaskRepository implements TaskRepository {
  @override
  Future<TaskLoadResult> load() async {
    return const TaskLoadResult(tasks: [], lists: [], entries: []);
  }

  @override
  Future<void> replace({
    required List<Task> tasks,
    required List<TaskList> lists,
    required List<TaskListEntry> entries,
  }) async {}

  @override
  Future<void> saveChanges({
    Iterable<Task> upsertTasks = const [],
    Iterable<String> deleteTaskIds = const [],
    Iterable<TaskList> upsertLists = const [],
    Iterable<String> deleteListIds = const [],
    Iterable<TaskListEntry> upsertEntries = const [],
    Iterable<String> deleteEntryTaskIds = const [],
  }) async {}
}

final class _MemoryCalendarRepository implements CalendarRepository {
  @override
  Future<CalendarLoadResult> load() async {
    return const CalendarLoadResult(events: [], anniversaries: []);
  }

  @override
  Future<void> replace({
    required List<CalendarEvent> events,
    required List<Anniversary> anniversaries,
  }) async {}

  @override
  Future<void> saveChanges({
    Iterable<CalendarEvent> upsertEvents = const [],
    Iterable<String> deleteEventIds = const [],
    Iterable<Anniversary> upsertAnniversaries = const [],
    Iterable<String> deleteAnniversaryIds = const [],
  }) async {}
}

final class _MemoryAccountService implements AccountService {
  @override
  bool get isBackendConnected => false;
  @override
  Future<AccountUser?> getCurrentUser() async => null;
  @override
  Future<AuthSession?> loadStoredSession() async => null;
  @override
  Future<void> logout() async {}
  @override
  Future<AuthSession> login({
    required String username,
    required String password,
  }) => throw UnimplementedError();
  @override
  Future<AuthSession> register({
    required String username,
    required String password,
    String? displayName,
  }) => throw UnimplementedError();
}

final class _MemoryCloudRepository implements CloudDataRepository {
  @override
  Future<CloudDataSnapshot> load(String scope) async =>
      const CloudDataSnapshot();
  @override
  Future<List<CloudManagementOperation>> loadOperations(String scope) async =>
      const [];
  @override
  Future<void> removeOperation(String scope, String operationId) async {}
  @override
  Future<void> reconcileOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  ) async {}
  @override
  Future<String?> loadRequestId(String scope, String requestKey) async => null;
  @override
  Future<void> saveRequestId(
    String scope,
    String requestKey,
    String requestId,
  ) async {}
  @override
  Future<void> removeRequestId(String scope, String requestKey) async {}
  @override
  Future<void> replace(
    String scope,
    CloudIndexStatus status,
    List<CloudIndexObject> objects,
  ) async {}
  @override
  Future<void> requireFullReseed(String scope, int generation) async {}
  @override
  Future<void> saveOperations(
    String scope,
    Iterable<CloudManagementOperation> operations,
  ) async {}
}

final class _MemoryCloudService implements CloudDataService {
  @override
  Future<CloudCurrentProjection> getCurrentProjection() =>
      throw UnimplementedError();

  @override
  Future<void> acknowledgeOperation(
    String operationId,
    int generation,
    String requestId, {
    required bool includeOperationId,
  }) async {}
  @override
  Future<CloudObjectDetail> getObject(
    String category,
    String objectId,
    int revision,
  ) => throw UnimplementedError();
  @override
  Future<List<CloudManagementOperation>> getOperations() async => const [];
  @override
  Future<CloudIndexStatus> getStatus() => throw UnimplementedError();
  @override
  Future<List<CloudIndexObject>> listObjects(String category, int revision) =>
      throw UnimplementedError();
  @override
  Future<CloudPurgePreview> previewPurge(
    CloudPurgeSelector selector,
    int revision,
  ) => throw UnimplementedError();
  @override
  Future<CloudManagementOperation> purge(
    CloudPurgePreview preview,
    String requestId,
  ) => throw UnimplementedError();
}
