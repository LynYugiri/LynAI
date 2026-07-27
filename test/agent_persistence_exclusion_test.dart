import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/agent_persistence.dart';
import 'package:lynai/models/agent_runtime.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/repositories/agent_persistence_repository.dart';
import 'package:lynai/services/backup_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  test('Agent runtime tables are excluded from backup archives', () async {
    final root = await Directory.systemTemp.createTemp('lynai_agent_backup_');
    final storage = StorageV2Service(rootDirectory: root);
    try {
      await StorageV2UpgradeService(storageV2: storage).ensureReady();
      final now = DateTime.utc(2026, 7, 27);
      await AgentPersistenceRepository(storage).createRun(
        AgentRunRecord(
          id: 'must-not-be-backed-up',
          status: AgentRunStatus.queued,
          createdAt: now,
          updatedAt: now,
        ),
      );
      final bytes = await BackupService(
        settingsProvider: SettingsProvider(storageV2: storage),
        modelConfigProvider: ModelConfigProvider(storageV2: storage),
        conversationProvider: ConversationProvider(storageV2: storage),
        featureProvider: FeatureProvider(storageV2: storage),
        roleplayProvider: RoleplayProvider(storageV2: storage),
        storageV2: storage,
        appVersionLoader: () async => 'test',
      ).exportZipBytes(const BackupSelection({}));

      final archive = ZipDecoder().decodeBytes(bytes);
      expect(archive.files.map((file) => file.name), ['manifest.json']);
      final archiveText = archive.files
          .where((file) => file.isFile)
          .map((file) => utf8.decode(file.content as List<int>))
          .join('\n');
      expect(archiveText, isNot(contains('must-not-be-backed-up')));
      expect(archiveText, isNot(contains('agentRuntime')));
      expect(
        jsonDecode(utf8.decode(archive.files.single.content as List<int>)),
        isNotNull,
      );
    } finally {
      await storage.close();
      if (await root.exists()) await root.delete(recursive: true);
    }
  });
}
