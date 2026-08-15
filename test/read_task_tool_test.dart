import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/lynai_call_identity.dart';
import 'package:lynai/services/lynai_function_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

Future<StorageV2Service> _readyStorage(Directory root) async {
  final storage = StorageV2Service(rootDirectory: root);
  await StorageV2UpgradeService(storageV2: storage).ensureReady();
  return storage;
}

void main() {
  test('tasks.read resolves exact id without title fallback', () async {
    SharedPreferences.setMockInitialValues({});
    final root = await Directory.systemTemp.createTemp('lynai_read_task_');
    final storage = await _readyStorage(root);
    try {
      final tasks = TaskProvider(storageV2: storage);
      await tasks.load();
      final listId = await tasks.addList('工作');
      final first = await tasks.addTask(title: '同名任务', listId: listId);
      final second = await tasks.addTask(title: '同名任务', listId: listId);

      Future<Map<String, dynamic>> call(String method, Map<String, dynamic> args) {
        return LynAIFunctionService().execute(
          LynAIFunctionCall(name: method, arguments: args),
          LynAIFunctionContext(
            identity: const LynAICallIdentity(type: LynAICallerType.system),
            tasks: tasks,
          ),
        );
      }

      final read = await call('tasks.read', {'id': second});
      expect(read['ok'], isTrue, reason: read.toString());
      expect(read['task']['id'], second);
      expect(read['task']['id'], isNot(first));

      final list = await call('taskLists.read', {'id': listId});
      expect(list['ok'], isTrue, reason: list.toString());
      expect(list['list']['id'], listId);

      final missing = await call('tasks.read', {'id': 'nonexistent'});
      expect(missing['ok'], isFalse);
    } finally {
      await storage.close();
      await root.delete(recursive: true);
    }
  });
}
