import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/backup_models.dart';
import 'package:lynai/models/composer_draft.dart';
import 'package:lynai/models/composer_reference.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/feature_provider.dart';
import 'package:lynai/providers/model_config_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/services/backup_service.dart';
import 'package:lynai/services/storage_v2_service.dart';
import 'package:lynai/services/storage_v2_upgrade_service.dart';

void main() {
  test('输入框草稿随对话分区备份并恢复附件文件', () async {
    final sourceRoot = await Directory.systemTemp.createTemp(
      'draft_backup_src_',
    );
    final targetRoot = await Directory.systemTemp.createTemp(
      'draft_backup_dst_',
    );
    final sourceStorage = await _readyStorage(sourceRoot);
    final targetStorage = await _readyStorage(targetRoot);
    try {
      final source = ConversationProvider(storageV2: sourceStorage);
      await source.loadConversations();
      final conversationId = _addConversation(source);
      final attachment = File('${sourceRoot.path}/notes.txt')
        ..writeAsStringSync('附件内容');
      source.saveComposerDraft(
        conversationId,
        ComposerDraft(
          segments: const [ComposerTextSegment('看下这份文件 ')],
          attachments: [
            ComposerDraftAttachment(
              path: attachment.path,
              name: 'notes.txt',
              size: attachment.lengthSync(),
              mimeType: 'text/plain',
            ),
          ],
        ),
      );
      // 未创建对话的草稿不该进备份：它有对话时才会被带出去。
      source.saveComposerDraft(
        null,
        const ComposerDraft(segments: [ComposerTextSegment('还没归属的草稿')]),
      );
      await source.flushPendingSaves();

      final bytes = await _service(source, sourceStorage).exportZipBytes(
        BackupSelection(
          const {BackupSection.conversations},
          conversationIds: {conversationId},
        ),
      );

      final target = ConversationProvider(storageV2: targetStorage);
      await target.loadConversations();
      final service = _service(target, targetStorage);
      final archive = await service.readZipBytes(bytes);
      expect(archive.data.composerDrafts!.keys, [conversationId]);
      await service.importArchive(
        archive,
        ImportPlan(
          selection: BackupSelection(
            const {BackupSection.conversations},
            conversationIds: {conversationId},
          ),
          mode: ImportMode.replaceSection,
        ),
      );

      final restored = target.composerDraftFor(conversationId);
      expect(
        restored.segments.whereType<ComposerTextSegment>().single.text,
        '看下这份文件 ',
      );
      expect(restored.attachments, hasLength(1));
      final restoredAttachment = restored.attachments.single;
      expect(restoredAttachment.name, 'notes.txt');
      expect(File(restoredAttachment.path).readAsStringSync(), '附件内容');
      expect(target.composerDraftFor(null).isEmpty, isTrue);
    } finally {
      await sourceStorage.close();
      await targetStorage.close();
      await sourceRoot.delete(recursive: true);
      await targetRoot.delete(recursive: true);
    }
  });

  test('未归档的草稿附件不把本机路径写进备份，并保留 Resource ID', () async {
    final sourceRoot = await Directory.systemTemp.createTemp(
      'draft_backup_missing_',
    );
    final sourceStorage = await _readyStorage(sourceRoot);
    try {
      final source = ConversationProvider(storageV2: sourceStorage);
      await source.loadConversations();
      final conversationId = _addConversation(source);
      const outsidePath = '/definitely/not/here/secret.png';
      source.saveComposerDraft(
        conversationId,
        const ComposerDraft(
          segments: [ComposerTextSegment('看下 ')],
          attachments: [
            ComposerDraftAttachment(
              resourceId: 'res-1',
              path: outsidePath,
              name: 'secret.png',
              size: 12,
              mimeType: 'image/png',
            ),
          ],
        ),
      );
      await source.flushPendingSaves();

      final service = _service(source, sourceStorage);
      final bytes = await service.exportZipBytes(
        BackupSelection(
          const {BackupSection.conversations},
          conversationIds: {conversationId},
        ),
      );
      final archive = await service.readZipBytes(bytes);
      final exported = archive
          .data
          .composerDrafts![conversationId]!
          .attachments
          .single;

      // 归档失败（文件缺失）时不能把导出机器的绝对路径写进备份。
      expect(exported.path, isEmpty);
      expect(exported.name, 'secret.png');
      // Resource ID 保留，恢复后仍可按 Resource 重新解析本机文件。
      expect(exported.resourceId, 'res-1');
    } finally {
      await sourceStorage.close();
      await sourceRoot.delete(recursive: true);
    }
  });
}

String _addConversation(ConversationProvider conversations) {
  final id = conversations.createConversationWithMessages(
    ConversationSettings(modelId: 'model'),
    messages: [
      (
        role: 'user',
        content: '甲会话',
        images: const [],
        composerSegments: const [],
      ),
      (
        role: 'assistant',
        content: '回复',
        images: const [],
        composerSegments: const [],
      ),
    ],
  );
  return id;
}

Future<StorageV2Service> _readyStorage(Directory root) async {
  final storage = StorageV2Service(rootDirectory: root);
  await StorageV2UpgradeService(storageV2: storage).ensureReady();
  return storage;
}

BackupService _service(
  ConversationProvider conversations,
  StorageV2Service storage,
) => BackupService(
  settingsProvider: SettingsProvider(storageV2: storage),
  modelConfigProvider: ModelConfigProvider(storageV2: storage),
  conversationProvider: conversations,
  featureProvider: FeatureProvider(storageV2: storage),
  roleplayProvider: RoleplayProvider(storageV2: storage),
  storageV2: storage,
  appVersionLoader: () async => 'test',
);
