import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/models/role_memory_entry.dart';
import 'package:lynai/providers/role_memory_provider.dart';
import 'package:lynai/services/lynai_permission_definitions.dart';

import 'support/memory_repositories.dart';

void main() {
  late MemoryRoleMemoryRepository repository;
  late RoleMemoryProvider provider;

  setUp(() {
    repository = MemoryRoleMemoryRepository();
    provider = RoleMemoryProvider(repository: repository);
  });

  test('角色之间完全隔离', () {
    provider.add('role-a', RoleMemoryProvider.targetMemory, 'A 的笔记');
    provider.add('role-b', RoleMemoryProvider.targetMemory, 'B 的笔记');

    expect(provider.entryTextsFor('role-a', RoleMemoryProvider.targetMemory), [
      'A 的笔记',
    ]);
    expect(provider.memoryBlockFor('role-a'), contains('A 的笔记'));
    expect(provider.memoryBlockFor('role-a'), isNot(contains('B 的笔记')));
  });

  test('add 去重且超出预算返回 current_entries', () {
    provider.updateLimits(memory: 10);
    provider.add('role-a', RoleMemoryProvider.targetMemory, '123456');

    final overflow = provider.add(
      'role-a',
      RoleMemoryProvider.targetMemory,
      'abc',
    );

    expect(overflow['success'], isFalse);
    expect(overflow['current_entries'], isNotNull);
  });

  test('applyBatch 原子提交：中途失败全部不落', () {
    provider.add('role-a', RoleMemoryProvider.targetMemory, '已有条目');

    final result = provider.applyBatch(
      'role-a',
      RoleMemoryProvider.targetMemory,
      [
        {'action': 'add', 'content': '新增条目'},
        {'action': 'remove', 'old_text': '不存在的条目'},
      ],
    );

    expect(result['success'], isFalse);
    expect(provider.entryTextsFor('role-a', RoleMemoryProvider.targetMemory), [
      '已有条目',
    ]);
  });

  test('removeRole 级联删除并持久化', () async {
    provider.add('role-a', RoleMemoryProvider.targetMemory, 'A');
    provider.add('role-a', RoleMemoryProvider.targetUser, '用户 A');
    provider.add('role-b', RoleMemoryProvider.targetMemory, 'B');

    provider.removeRole('role-a');
    await provider.flushPendingSaves();

    expect(
      repository.entries.any((entry) => entry.roleId == 'role-a'),
      isFalse,
    );
    expect(repository.entries.any((entry) => entry.roleId == 'role-b'), isTrue);
  });

  test('nudge 每 N 轮触发，写入成功后重置', () {
    expect(provider.takeNudgeIfDue('role-a', nudgeInterval: 3), isEmpty);

    provider.noteUserTurn('role-a');
    provider.noteUserTurn('role-a');
    expect(provider.takeNudgeIfDue('role-a', nudgeInterval: 3), isEmpty);

    provider.noteUserTurn('role-a');
    expect(provider.takeNudgeIfDue('role-a', nudgeInterval: 3), isNotEmpty);
    expect(provider.takeNudgeIfDue('role-a', nudgeInterval: 3), isEmpty);

    provider.noteUserTurn('role-a');
    provider.noteUserTurn('role-a');
    provider.add('role-a', RoleMemoryProvider.targetMemory, '写入一条');
    provider.noteUserTurn('role-a');
    provider.noteUserTurn('role-a');
    expect(provider.takeNudgeIfDue('role-a', nudgeInterval: 3), isEmpty);
  });

  test('合并失败超过 3 次后返回终结性错误', () {
    provider.updateLimits(memory: 10);
    provider.add('role-a', RoleMemoryProvider.targetMemory, '123456789');

    for (var i = 0; i < 3; i++) {
      final result = provider.add(
        'role-a',
        RoleMemoryProvider.targetMemory,
        'overflow',
      );
      expect(result['done'], isNot(true));
    }
    final terminal = provider.add(
      'role-a',
      RoleMemoryProvider.targetMemory,
      'overflow-again',
    );
    expect(terminal['done'], isTrue);
    expect(terminal['success'], isFalse);

    provider.resetConsolidationFailures('role-a');
    final retry = provider.add(
      'role-a',
      RoleMemoryProvider.targetMemory,
      'overflow-after-reset',
    );
    expect(retry['done'], isNot(true));
  });

  test('角色记忆读写权限已加入 Agent 可分配权限', () {
    expect(
      LynAIPermissions.agentAssignable,
      contains(LynAIPermissions.roleMemoryRead),
    );
    expect(
      LynAIPermissions.agentAssignable,
      contains(LynAIPermissions.roleMemoryWrite),
    );
    expect(
      LynAIPermissions.defaultAgent,
      contains(LynAIPermissions.roleMemoryRead),
    );
    expect(
      LynAIPermissions.defaultAgent,
      contains(LynAIPermissions.roleMemoryWrite),
    );
  });

  test('replaceAt/removeAt 按索引精确编辑', () {
    provider.add('role-a', RoleMemoryProvider.targetMemory, 'abc');
    provider.add('role-a', RoleMemoryProvider.targetMemory, 'abcd');

    final replaced = provider.replaceAt(
      'role-a',
      RoleMemoryProvider.targetMemory,
      0,
      'xyz',
    );
    expect(replaced['success'], isTrue);
    expect(provider.entryTextsFor('role-a', RoleMemoryProvider.targetMemory), [
      'xyz',
      'abcd',
    ]);

    final removed = provider.removeAt(
      'role-a',
      RoleMemoryProvider.targetMemory,
      1,
    );
    expect(removed['success'], isTrue);
    expect(provider.entryTextsFor('role-a', RoleMemoryProvider.targetMemory), [
      'xyz',
    ]);
  });

  test('nudge 计数跨 Provider 重载恢复', () async {
    provider.noteUserTurn('role-a');
    provider.noteUserTurn('role-a');
    await provider.flushPendingSaves();

    final reloaded = RoleMemoryProvider(repository: repository);
    await reloaded.load();

    expect(reloaded.takeNudgeIfDue('role-a', nudgeInterval: 3), isEmpty);
    reloaded.noteUserTurn('role-a');
    expect(reloaded.takeNudgeIfDue('role-a', nudgeInterval: 3), isNotEmpty);
  });

  test('load 去重并恢复条目', () async {
    final now = DateTime.now();
    repository.entries = [
      RoleMemoryEntry(
        id: '1',
        roleId: 'role-a',
        target: RoleMemoryProvider.targetMemory,
        entry: '重复条目',
        sortOrder: 0,
        createdAt: now,
        updatedAt: now,
      ),
      RoleMemoryEntry(
        id: '2',
        roleId: 'role-a',
        target: RoleMemoryProvider.targetMemory,
        entry: '重复条目',
        sortOrder: 1,
        createdAt: now,
        updatedAt: now,
      ),
    ];

    await provider.load();

    expect(provider.entryTextsFor('role-a', RoleMemoryProvider.targetMemory), [
      '重复条目',
    ]);
  });

  test('备份分区暴露角色记忆数据', () {
    final now = DateTime.now();
    final data = BackupData(
      roleMemoryEntries: [
        RoleMemoryEntry(
          id: '1',
          roleId: 'role-a',
          target: RoleMemoryProvider.targetMemory,
          entry: '条目',
          createdAt: now,
          updatedAt: now,
        ),
      ],
      roleMemoryCounters: const {'role-a': 3},
    );

    expect(BackupSection.roleMemory.key, 'roleMemory');
    expect(BackupSection.roleMemory.label, '角色记忆');
    expect(data.hasSection(BackupSection.roleMemory), isTrue);
  });
}
