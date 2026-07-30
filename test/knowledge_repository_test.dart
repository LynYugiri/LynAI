import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/knowledge_entry.dart';
import 'package:lynai/models/knowledge_explanation.dart';
import 'package:lynai/models/knowledge_source.dart';
import 'package:lynai/repositories/knowledge_repository.dart';
import 'package:lynai/models/sync_change.dart';
import 'package:lynai/services/storage_v2_database.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test('knowledge wire timestamps are normalized to UTC RFC3339', () {
    final local = DateTime(2026, 7, 29, 10);
    final json = KnowledgeBase(
      id: 'base',
      name: 'Base',
      enabled: true,
      sortOrder: 0,
      createdAt: local,
      updatedAt: local,
    ).toJson();

    expect(json['createdAt'], endsWith('Z'));
    expect(json['updatedAt'], endsWith('Z'));
    expect(DateTime.parse(json['createdAt'] as String).isUtc, isTrue);
  });

  test(
    'knowledge repository ignores legacy settings and writes row types',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_knowledge_repo_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      try {
        final repository = KnowledgeRepository(storageV2: storage);
        final now = DateTime(2026, 7, 29, 10);
        final base = KnowledgeBase(
          id: 'base',
          name: 'Base',
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        final category = KnowledgeCategory(
          id: 'category',
          knowledgeBaseId: base.id,
          name: 'Default',
          alias: 'default',
          annotationRule: '标注稳定事实',
          explanationPrompt: '解释该事实',
          colorValue: 0xff336699,
          autoAnnotate: true,
          modelConfigId: 'model-1',
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        final entry = KnowledgeEntry(
          id: 'entry',
          knowledgeBaseId: base.id,
          categoryId: category.id,
          title: 'Fact',
          content: 'Content',
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        final source = KnowledgeSource(
          id: 'source',
          knowledgeBaseId: base.id,
          entryId: entry.id,
          title: 'Web',
          url: 'https://example.com',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        final explanation = KnowledgeExplanation(
          id: 'explanation',
          knowledgeBaseId: base.id,
          entryId: entry.id,
          title: 'Why',
          content: 'Because',
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        await repository.replace(
          KnowledgeLoadResult(
            bases: [base],
            categories: [category],
            entries: [entry],
            sources: [source],
            explanations: [explanation],
          ),
        );

        final loaded = await repository.load();
        expect(loaded.bases.single.toJson(), base.toJson());
        expect(loaded.categories.single.toJson(), category.toJson());
        expect(loaded.entries.single.toJson(), entry.toJson());
        expect(loaded.sources.single.toJson(), source.toJson());
        expect(loaded.explanations.single.toJson(), explanation.toJson());
        expect(
          (await storage.loadDataFile(
            'knowledge.json',
          )).containsKey('settings'),
          isFalse,
        );

        await storage.activateSyncScope('cloud:test', deviceId: 'device-1');
        await repository.saveChanges(
          upsertCategories: [category.copyWith(annotationRule: '更新规则')],
          upsertSources: [source],
          upsertExplanations: [explanation],
        );
        final outbox = await storage.loadSyncOutbox('cloud:test');
        final categoryChange = outbox.singleWhere(
          (item) => item.table == 'knowledge_categories',
        );
        expect(categoryChange.data, containsPair('alias', 'default'));
        expect(categoryChange.data, containsPair('annotationRule', '更新规则'));
        expect(categoryChange.data, containsPair('explanationPrompt', '解释该事实'));
        expect(categoryChange.data, containsPair('colorValue', 0xff336699));
        expect(categoryChange.data, containsPair('autoAnnotate', true));
        expect(categoryChange.data, containsPair('modelConfigId', 'model-1'));
        expect(
          outbox.singleWhere((item) => item.table == 'knowledge_sources').data,
          containsPair('knowledgeBaseId', base.id),
        );
        expect(
          outbox
              .singleWhere((item) => item.table == 'knowledge_explanations')
              .data,
          containsPair('knowledgeBaseId', base.id),
        );
        expect(
          outbox.where((item) => item.table == 'knowledge_settings'),
          isEmpty,
        );
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test('legacy remote defaults are ignored while cursor advances', () async {
    final root = await Directory.systemTemp.createTemp(
      'lynai_knowledge_settings_',
    );
    final storage = StorageV2Service(rootDirectory: root);
    try {
      final now = DateTime.utc(2026, 7, 29);
      SyncRemoteOperation remote(
        String table,
        String id,
        Map<String, dynamic> data,
        int seq,
      ) => (
        table: table,
        op: 'upsert',
        data: data,
        change: SyncChange(
          seq: seq,
          changeId: 'settings-change-$seq',
          deviceId: 'device',
          clientCreatedAt: now,
          table: table,
          op: 'upsert',
          recordId: id,
          data: data,
        ),
      );
      final timestamp = now.toIso8601String();
      await storage.applyRemoteChanges('scope', [
        remote('knowledge_settings', 'global', {
          'id': 'global',
          'defaultKnowledgeBaseId': 'base',
          'defaultCategoryId': 'category',
          'updatedAt': timestamp,
        }, 3),
        remote('knowledge_categories', 'category', {
          'id': 'category',
          'knowledgeBaseId': 'base',
          'name': 'Default',
          'alias': 'default',
          'autoAnnotate': true,
          'isDefault': true,
          'enabled': true,
          'sortOrder': 0,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        }, 2),
        remote('knowledge_bases', 'base', {
          'id': 'base',
          'name': 'Base',
          'enabled': true,
          'sortOrder': 0,
          'createdAt': timestamp,
          'updatedAt': timestamp,
        }, 1),
      ], 3);

      final knowledge = await storage.loadDataFile('knowledge.json');
      expect(knowledge, isNot(contains('settings')));
      expect(
        (knowledge['categories'] as List).single,
        isNot(contains('isDefault')),
      );
      expect(await storage.syncSince('scope'), 3);
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('remote entry rejects a category from another knowledge base', () async {
    final root = await Directory.systemTemp.createTemp('lynai_knowledge_fk_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      final now = DateTime.utc(2026, 7, 29).toIso8601String();
      SyncRemoteOperation remote(
        String table,
        String id,
        Map<String, dynamic> data,
        int seq,
      ) => (
        table: table,
        op: 'upsert',
        data: data,
        change: SyncChange(
          seq: seq,
          changeId: 'change-$seq',
          deviceId: 'device',
          clientCreatedAt: DateTime.utc(2026, 7, 29),
          table: table,
          op: 'upsert',
          recordId: id,
          data: data,
        ),
      );
      await storage.applyRemoteChanges('scope', [
        remote('knowledge_bases', 'base-a', {
          'id': 'base-a',
          'name': 'A',
          'enabled': true,
          'sortOrder': 0,
          'createdAt': now,
          'updatedAt': now,
        }, 1),
        remote('knowledge_bases', 'base-b', {
          'id': 'base-b',
          'name': 'B',
          'enabled': true,
          'sortOrder': 1,
          'createdAt': now,
          'updatedAt': now,
        }, 2),
        remote('knowledge_categories', 'category-b', {
          'id': 'category-b',
          'knowledgeBaseId': 'base-b',
          'name': 'B category',
          'alias': 'category_b',
          'annotationRule': '',
          'explanationPrompt': '',
          'colorValue': 0,
          'autoAnnotate': false,
          'isDefault': false,
          'enabled': true,
          'sortOrder': 0,
          'createdAt': now,
          'updatedAt': now,
        }, 3),
      ], 3);

      await expectLater(
        storage.applyRemoteChanges('scope', [
          remote('knowledge_entries', 'entry-a', {
            'id': 'entry-a',
            'knowledgeBaseId': 'base-a',
            'categoryId': 'category-b',
            'title': 'Invalid',
            'content': '',
            'enabled': true,
            'sortOrder': 0,
            'createdAt': now,
            'updatedAt': now,
          }, 4),
        ], 4),
        throwsStateError,
      );
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
