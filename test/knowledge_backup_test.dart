import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/models/knowledge_base.dart';
import 'package:lynai/models/knowledge_category.dart';
import 'package:lynai/models/knowledge_entry.dart';
import 'package:lynai/models/knowledge_explanation.dart';
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
    'schema 13 omits defaults and imports children for equal base',
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
        final sourceKnowledge = KnowledgeProvider(storageV2: sourceStorage);
        await sourceKnowledge.replaceAll(
          knowledgeBases: [base],
          categories: [category],
          entries: [entry],
          sources: const [],
          explanations: const [],
        );
        final source = _service(sourceStorage, sourceKnowledge);
        final selection = BackupSelection(
          const {BackupSection.knowledge},
          knowledgeBaseIds: {base.id},
        );
        final archive = await source.readZipBytes(
          await source.exportZipBytes(selection),
        );
        expect(archive.manifest['schemaVersion'], 14);
        expect(
          archive.data.knowledgeCategories?.single.toJson(),
          isNot(contains('isDefault')),
        );

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
        expect(targetKnowledge.categoryById(category.id), isNotNull);
        expect(targetKnowledge.entryById(entry.id), isNotNull);
      } finally {
        await sourceStorage.close();
        await targetStorage.close();
        if (await sourceRoot.exists()) await sourceRoot.delete(recursive: true);
        if (await targetRoot.exists()) await targetRoot.delete(recursive: true);
      }
    },
  );

  test(
    'schema 11 and 12 import proper_noun conflicts through provider normalization',
    () async {
      final root = await Directory.systemTemp.createTemp(
        'lynai_knowledge_backup_legacy_defaults_',
      );
      final storage = StorageV2Service(rootDirectory: root);
      try {
        final now = DateTime.utc(2026, 7, 29);
        final base = _base('base', now);
        final category = _category('category', base.id, now);
        final knowledge = KnowledgeProvider(storageV2: storage);
        await knowledge.replaceAll(
          knowledgeBases: [base],
          categories: [category],
          entries: const [],
          sources: const [],
          explanations: const [],
        );
        final service = _service(storage, knowledge);
        final bytes = await service.exportZipBytes(
          _knowledgeSelection(base.id),
        );
        for (final schemaVersion in [11, 12]) {
          final archive = await service.readZipBytes(
            _withLegacyKnowledgeDefaults(
              bytes,
              schemaVersion,
              alias: KnowledgeProvider.properNounAlias,
            ),
          );
          expect(archive.data.knowledgeCategories?.single.id, category.id);
          expect(
            archive.data.knowledgeCategories?.single.toJson(),
            isNot(contains('isDefault')),
          );
          final targetRoot = await Directory.systemTemp.createTemp(
            'lynai_knowledge_backup_legacy_target_',
          );
          final targetStorage = StorageV2Service(rootDirectory: targetRoot);
          try {
            final targetKnowledge = KnowledgeProvider(storageV2: targetStorage);
            await targetKnowledge.load();
            await _service(targetStorage, targetKnowledge).importArchive(
              archive,
              ImportPlan(
                selection: _knowledgeSelection(base.id),
                mode: ImportMode.addOnly,
              ),
            );
            expect(
              targetKnowledge.categoryById(category.id)?.alias,
              'proper_noun_category',
            );
            expect(
              targetKnowledge.categoryById(category.id)?.updatedAt,
              category.updatedAt,
            );
          } finally {
            await targetStorage.close();
            if (await targetRoot.exists()) {
              await targetRoot.delete(recursive: true);
            }
          }
        }
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
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
        final knowledge = KnowledgeProvider(storageV2: storage);
        await knowledge.replaceAll(
          knowledgeBases: [base],
          categories: [localCategory],
          entries: [localEntry],
          sources: [localSource],
          explanations: [localExplanation],
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
      } finally {
        await storage.close();
        if (await root.exists()) await root.delete(recursive: true);
      }
    },
  );

  test('merge keepLocal preserves conflicts and adds children', () async {
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
      final knowledge = KnowledgeProvider(storageV2: storage);
      await knowledge.replaceAll(
        knowledgeBases: [localBase],
        categories: [localCategory],
        entries: [localEntry],
        sources: const [],
        explanations: const [],
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

      expect(knowledge.knowledgeBaseById(localBase.id)?.name, 'Local');
      expect(knowledge.categoryById(localCategory.id)?.name, 'Default');
      expect(knowledge.entryById('entry')?.title, 'Local');
      expect(knowledge.entryById('new-entry')?.title, 'New');
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

  test('partial knowledge backup replaces only selected bases', () async {
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
      final knowledge = KnowledgeProvider(storageV2: storage);
      await knowledge.replaceAll(
        knowledgeBases: [localBase],
        categories: [localCategory],
        entries: const [],
        sources: const [],
        explanations: const [],
      );

      await _service(storage, knowledge).importArchive(
        _archive(bases: [incomingBase], categories: [incomingCategory]),
        ImportPlan(
          selection: _knowledgeSelection(incomingBase.id),
          mode: ImportMode.replaceSection,
        ),
      );

      expect(
        knowledge.knowledgeBases.map((item) => item.id),
        containsAll(['local', 'incoming']),
      );
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });

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
        expect(knowledge.knowledgeBaseById(localBase.id), isNotNull);
        expect(knowledge.categoryById('category'), isNull);
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
  ),
);

List<int> _withLegacyKnowledgeDefaults(
  List<int> bytes,
  int schemaVersion, {
  String? alias,
}) {
  final source = ZipDecoder().decodeBytes(bytes);
  final archive = Archive();
  for (final file in source.files) {
    var content = List<int>.from(file.content as List);
    if (file.name == 'manifest.json') {
      final manifest = jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      manifest['schemaVersion'] = schemaVersion;
      content = utf8.encode(jsonEncode(manifest));
    } else if (file.name == 'knowledge.json') {
      final knowledge =
          jsonDecode(utf8.decode(content)) as Map<String, dynamic>;
      for (final category
          in (knowledge['categories'] as List).whereType<Map>()) {
        category['isDefault'] = true;
        if (alias != null) category['alias'] = alias;
      }
      knowledge['settings'] = {
        'defaultKnowledgeBaseId': 'base',
        'defaultCategoryId': 'category',
        'updatedAt': '2026-07-29T00:00:00Z',
      };
      content = utf8.encode(jsonEncode(knowledge));
    }
    archive.addFile(ArchiveFile(file.name, content.length, content));
  }
  return ZipEncoder().encode(archive);
}

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
