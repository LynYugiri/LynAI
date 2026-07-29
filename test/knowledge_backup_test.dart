import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/knowledge_entry.dart';
import 'package:lynai/models/knowledge_explanation.dart';
import 'package:lynai/models/knowledge_settings.dart';
import 'package:lynai/models/knowledge_source.dart';
import 'package:lynai/providers/calendar_provider.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/knowledge_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/providers/task_provider.dart';
import 'package:lynai/services/backup_service.dart';
import 'package:lynai/services/storage_v2_service.dart';

void main() {
  test(
    'schema 12 round-trips settings and imports children for equal base',
    () async {
      final sourceRoot = await Directory.systemTemp.createTemp(
        'lynai_knowledge_backup_source_',
      );
      final targetRoot = await Directory.systemTemp.createTemp(
        'lynai_knowledge_backup_target_',
      );
      final sourceStorage = StorageV2Service(rootDirectory: sourceRoot);
      final targetStorage = StorageV2Service(rootDirectory: targetRoot);
      try {
        final now = DateTime.utc(2026, 7, 29);
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
          autoAnnotate: true,
          isDefault: true,
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
        final settings = KnowledgeSettings(
          defaultKnowledgeBaseId: base.id,
          defaultCategoryId: category.id,
          updatedAt: now,
        );
        final sourceKnowledge = KnowledgeProvider(storageV2: sourceStorage);
        await sourceKnowledge.replaceAll(
          knowledgeBases: [base],
          categories: [category],
          entries: [entry],
          sources: const [],
          explanations: const [],
          settings: settings,
        );
        final source = _service(sourceStorage, sourceKnowledge);
        final selection = BackupSelection(
          const {BackupSection.knowledge},
          knowledgeBaseIds: {base.id},
        );
        final archive = await source.readZipBytes(
          await source.exportZipBytes(selection),
        );
        expect(archive.manifest['schemaVersion'], 12);
        expect(archive.data.knowledgeSettings?.toJson(), settings.toJson());

        final targetKnowledge = KnowledgeProvider(storageV2: targetStorage);
        await targetKnowledge.replaceAll(
          knowledgeBases: [base],
          categories: const [],
          entries: const [],
          sources: const [],
          explanations: const [],
        );
        await _service(targetStorage, targetKnowledge).importArchive(
          archive,
          ImportPlan(selection: selection, mode: ImportMode.addOnly),
        );
        expect(targetKnowledge.categories.single.id, category.id);
        expect(targetKnowledge.entries.single.id, entry.id);
        expect(targetKnowledge.settings.defaultKnowledgeBaseId, base.id);
        expect(targetKnowledge.settings.defaultCategoryId, category.id);
      } finally {
        await sourceStorage.close();
        await targetStorage.close();
        if (await sourceRoot.exists()) await sourceRoot.delete(recursive: true);
        if (await targetRoot.exists()) await targetRoot.delete(recursive: true);
      }
    },
  );

  test(
    'addOnly merges knowledge children by ID without replacing local',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_knowledge_backup_add_only_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      try {
        final now = DateTime.utc(2026, 7, 29);
        final base = _base('base', now);
        final localCategory = _category(
          'category',
          base.id,
          now,
          name: 'Local',
        );
        final localEntry = _entry(
          'entry',
          base.id,
          localCategory.id,
          now,
          title: 'Local',
        );
        final localSource = _source(
          'source',
          base.id,
          localEntry.id,
          now,
          title: 'Local',
        );
        final localExplanation = _explanation(
          'explanation',
          base.id,
          localEntry.id,
          now,
          title: 'Local',
        );
        final localSettings = KnowledgeSettings(
          defaultKnowledgeBaseId: base.id,
          defaultCategoryId: localCategory.id,
          updatedAt: now,
        );
        final knowledge = KnowledgeProvider(storageV2: storage);
        await knowledge.replaceAll(
          knowledgeBases: [base],
          categories: [localCategory],
          entries: [localEntry],
          sources: [localSource],
          explanations: [localExplanation],
          settings: localSettings,
        );
        final newCategory = _category(
          'new-category',
          base.id,
          now,
          name: 'New',
          alias: 'new',
        );
        final newEntry = _entry(
          'new-entry',
          base.id,
          newCategory.id,
          now,
          title: 'New',
        );
        final archive = _archive(
          bases: [base],
          categories: [
            localCategory.copyWith(name: 'Incoming'),
            newCategory,
          ],
          entries: [
            localEntry.copyWith(title: 'Incoming'),
            newEntry,
          ],
          sources: [
            localSource.copyWith(title: 'Incoming'),
            _source('new-source', base.id, newEntry.id, now, title: 'New'),
          ],
          explanations: [
            localExplanation.copyWith(title: 'Incoming'),
            _explanation(
              'new-explanation',
              base.id,
              newEntry.id,
              now,
              title: 'New',
            ),
          ],
          settings: KnowledgeSettings(
            defaultKnowledgeBaseId: base.id,
            defaultCategoryId: localCategory.id,
            updatedAt: now.add(const Duration(hours: 1)),
          ),
        );

        await _service(storage, knowledge).importArchive(
          archive,
          ImportPlan(
            selection: _knowledgeSelection(base.id),
            mode: ImportMode.addOnly,
          ),
        );

        expect(knowledge.categoryById('category')?.name, 'Local');
        expect(knowledge.categoryById('new-category')?.name, 'New');
        expect(
          knowledge.entries.map((item) => item.id),
          containsAll(['entry', 'new-entry']),
        );
        expect(knowledge.entryById('entry')?.title, 'Local');
        expect(
          knowledge.sources.map((item) => item.id),
          containsAll(['source', 'new-source']),
        );
        expect(knowledge.sources.first.title, 'Local');
        expect(
          knowledge.explanations.map((item) => item.id),
          containsAll(['explanation', 'new-explanation']),
        );
        expect(knowledge.explanations.first.title, 'Local');
        expect(knowledge.settings.toJson(), localSettings.toJson());
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'merge keepLocal preserves conflicts, adds children, and keeps settings',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_knowledge_backup_keep_local_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      try {
        final now = DateTime.utc(2026, 7, 29);
        final localBase = _base('base', now, name: 'Local');
        final localCategory = _category('category', localBase.id, now);
        final localEntry = _entry(
          'entry',
          localBase.id,
          localCategory.id,
          now,
          title: 'Local',
        );
        final localSettings = KnowledgeSettings(
          defaultKnowledgeBaseId: localBase.id,
          defaultCategoryId: localCategory.id,
          updatedAt: now,
        );
        final knowledge = KnowledgeProvider(storageV2: storage);
        await knowledge.replaceAll(
          knowledgeBases: [localBase],
          categories: [localCategory],
          entries: [localEntry],
          sources: const [],
          explanations: const [],
          settings: localSettings,
        );
        final incomingBase = localBase.copyWith(name: 'Incoming');
        final newEntry = _entry(
          'new-entry',
          localBase.id,
          localCategory.id,
          now,
          title: 'New',
        );
        final archive = _archive(
          bases: [incomingBase],
          categories: [localCategory.copyWith(name: 'Incoming')],
          entries: [
            localEntry.copyWith(title: 'Incoming'),
            newEntry,
          ],
          settings: KnowledgeSettings(
            defaultKnowledgeBaseId: incomingBase.id,
            defaultCategoryId: localCategory.id,
            updatedAt: now.add(const Duration(hours: 1)),
          ),
        );

        await _service(storage, knowledge).importArchive(
          archive,
          ImportPlan(
            selection: _knowledgeSelection(localBase.id),
            mode: ImportMode.merge,
            conflictActions: const {
              'knowledge:base': ImportConflictAction.keepLocal,
            },
          ),
        );

        expect(knowledge.knowledgeBases.single.name, 'Local');
        expect(knowledge.categories.single.name, 'Default');
        expect(knowledge.entryById('entry')?.title, 'Local');
        expect(knowledge.entryById('new-entry')?.title, 'New');
        expect(knowledge.settings.toJson(), localSettings.toJson());
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'partial knowledge backup with empty settings keeps local defaults',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_knowledge_backup_partial_settings_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      try {
        final now = DateTime.utc(2026, 7, 29);
        final localBase = _base('local', now);
        final localCategory = _category('local-category', localBase.id, now);
        final incomingBase = _base('incoming', now);
        final incomingCategory = _category(
          'incoming-category',
          incomingBase.id,
          now,
          alias: 'incoming',
        );
        final localSettings = KnowledgeSettings(
          defaultKnowledgeBaseId: localBase.id,
          defaultCategoryId: localCategory.id,
          updatedAt: now,
        );
        final knowledge = KnowledgeProvider(storageV2: storage);
        await knowledge.replaceAll(
          knowledgeBases: [localBase],
          categories: [localCategory],
          entries: const [],
          sources: const [],
          explanations: const [],
          settings: localSettings,
        );

        await _service(storage, knowledge).importArchive(
          _archive(
            bases: [incomingBase],
            categories: [incomingCategory],
            settings: KnowledgeSettings(updatedAt: now),
          ),
          ImportPlan(
            selection: _knowledgeSelection(incomingBase.id),
            mode: ImportMode.replaceSection,
          ),
        );

        expect(knowledge.settings.toJson(), localSettings.toJson());
        expect(
          knowledge.knowledgeBases.map((item) => item.id),
          containsAll(['local', 'incoming']),
        );
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test(
    'invalid cross-base knowledge archive fails before replacement',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_knowledge_backup_atomic_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      try {
        final now = DateTime.utc(2026, 7, 29);
        final localBase = KnowledgeBase(
          id: 'local',
          name: 'Local',
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        final knowledge = KnowledgeProvider(storageV2: storage);
        await knowledge.replaceAll(
          knowledgeBases: [localBase],
          categories: const [],
          entries: const [],
          sources: const [],
          explanations: const [],
        );
        final incomingBase = localBase.copyWith(
          id: 'incoming',
          name: 'Incoming',
        );
        final otherBase = localBase.copyWith(id: 'other', name: 'Other');
        final invalidCategory = KnowledgeCategory(
          id: 'category',
          knowledgeBaseId: otherBase.id,
          name: 'Invalid',
          alias: 'invalid',
          isDefault: false,
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        final invalidEntry = KnowledgeEntry(
          id: 'entry',
          knowledgeBaseId: incomingBase.id,
          categoryId: invalidCategory.id,
          title: 'Invalid',
          content: '',
          enabled: true,
          sortOrder: 0,
          createdAt: now,
          updatedAt: now,
        );
        final archive = BackupArchiveData(
          manifest: {
            'schemaVersion': 12,
            'sections': {
              'knowledge': {
                'enabled': true,
                'files': ['knowledge.json'],
              },
            },
          },
          data: BackupData(
            knowledgeBases: [incomingBase, otherBase],
            knowledgeCategories: [invalidCategory],
            knowledgeEntries: [invalidEntry],
            knowledgeSources: const [],
            knowledgeExplanations: const [],
            knowledgeSettings: KnowledgeSettings(updatedAt: now),
          ),
        );
        final selection = BackupSelection(
          const {BackupSection.knowledge},
          knowledgeBaseIds: {incomingBase.id, otherBase.id},
        );
        await expectLater(
          _service(storage, knowledge).importArchive(
            archive,
            ImportPlan(selection: selection, mode: ImportMode.replaceSection),
          ),
          throwsFormatException,
        );
        expect(knowledge.knowledgeBases.single.id, localBase.id);
        expect(knowledge.categories, isEmpty);
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );
}

KnowledgeBase _base(String id, DateTime now, {String name = 'Base'}) =>
    KnowledgeBase(
      id: id,
      name: name,
      enabled: true,
      sortOrder: 0,
      createdAt: now,
      updatedAt: now,
    );

KnowledgeCategory _category(
  String id,
  String baseId,
  DateTime now, {
  String name = 'Default',
  String alias = 'default',
}) => KnowledgeCategory(
  id: id,
  knowledgeBaseId: baseId,
  name: name,
  alias: alias,
  autoAnnotate: true,
  isDefault: true,
  enabled: true,
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);

KnowledgeEntry _entry(
  String id,
  String baseId,
  String categoryId,
  DateTime now, {
  required String title,
}) => KnowledgeEntry(
  id: id,
  knowledgeBaseId: baseId,
  categoryId: categoryId,
  title: title,
  content: '',
  enabled: true,
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);

KnowledgeSource _source(
  String id,
  String baseId,
  String entryId,
  DateTime now, {
  required String title,
}) => KnowledgeSource(
  id: id,
  knowledgeBaseId: baseId,
  entryId: entryId,
  title: title,
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);

KnowledgeExplanation _explanation(
  String id,
  String baseId,
  String entryId,
  DateTime now, {
  required String title,
}) => KnowledgeExplanation(
  id: id,
  knowledgeBaseId: baseId,
  entryId: entryId,
  title: title,
  content: '',
  sortOrder: 0,
  createdAt: now,
  updatedAt: now,
);

BackupSelection _knowledgeSelection(String baseId) => BackupSelection(
  const {BackupSection.knowledge},
  knowledgeBaseIds: {baseId},
);

BackupArchiveData _archive({
  required List<KnowledgeBase> bases,
  List<KnowledgeCategory> categories = const [],
  List<KnowledgeEntry> entries = const [],
  List<KnowledgeSource> sources = const [],
  List<KnowledgeExplanation> explanations = const [],
  KnowledgeSettings? settings,
}) => BackupArchiveData(
  manifest: const {
    'schemaVersion': 12,
    'sections': {
      'knowledge': {
        'enabled': true,
        'files': ['knowledge.json'],
      },
    },
  },
  data: BackupData(
    knowledgeBases: bases,
    knowledgeCategories: categories,
    knowledgeEntries: entries,
    knowledgeSources: sources,
    knowledgeExplanations: explanations,
    knowledgeSettings: settings,
  ),
);

BackupService _service(StorageV2Service storage, KnowledgeProvider knowledge) =>
    BackupService(
      settingsProvider: SettingsProvider(storageV2: storage),
      modelConfigProvider: ModelConfigProvider(storageV2: storage),
      conversationProvider: ConversationProvider(storageV2: storage),
      featureProvider: FeatureProvider(storageV2: storage),
      roleplayProvider: RoleplayProvider(storageV2: storage),
      taskProvider: TaskProvider(storageV2: storage),
      knowledgeProvider: knowledge,
      calendarProvider: CalendarProvider(storageV2: storage),
      storageV2: storage,
      appVersionLoader: () async => 'test',
    );
