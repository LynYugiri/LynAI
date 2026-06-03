import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/roleplay.dart';
import 'package:lynai/providers/conversation_provider.dart';
import 'package:lynai/providers/roleplay_provider.dart';
import 'package:lynai/providers/settings_provider.dart';
import 'package:lynai/services/legacy_resource_migration_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'LegacyResourceMigrationService copies old document resources',
    () async {
      SharedPreferences.setMockInitialValues({});
      final legacyRoot = await Directory.systemTemp.createTemp(
        'lynai_legacy_resources_',
      );
      final targetRoot = await Directory.systemTemp.createTemp(
        'lynai_target_resources_',
      );
      try {
        final background = await _writeFile(legacyRoot, 'backgrounds/bg.png', [
          1,
          2,
          3,
        ]);
        final chatAttachment = await _writeFile(
          legacyRoot,
          'message_images/chat.png',
          [4, 5, 6],
        );
        final roleplayAttachment = await _writeFile(
          legacyRoot,
          'roleplay_attachments/role.txt',
          [7, 8, 9],
        );

        final settingsProvider = SettingsProvider();
        final conversationProvider = ConversationProvider();
        final roleplayProvider = RoleplayProvider();
        await settingsProvider.replaceSettings(
          AppSettings.defaults().copyWith(backgroundImagePath: background.path),
        );
        final now = DateTime(2026);
        await conversationProvider.replaceConversations([
          Conversation(
            id: 'c1',
            title: 'chat',
            messages: [
              Message(
                id: 'm1',
                role: 'user',
                content: '',
                images: [
                  MessageImage(
                    path: chatAttachment.path,
                    name: 'chat.png',
                    size: 3,
                    mimeType: 'image/png',
                  ),
                ],
                timestamp: now,
              ),
            ],
            modelId: 'm1',
            createdAt: now,
            updatedAt: now,
          ),
        ]);
        await roleplayProvider.replaceData(
          scenarios: [
            RoleplayScenario(
              id: 's1',
              title: 'scene',
              scenario: 'scene',
              director: const RoleplayDirector(),
              defaultPlayer: const RoleplayParticipant(
                id: 'player',
                name: '我',
                systemPrompt: '',
                isPlayer: true,
              ),
              createdAt: now,
              updatedAt: now,
            ),
          ],
          threads: [
            RoleplayThread(
              id: 't1',
              scenarioId: 's1',
              title: 'thread',
              scenarioTitle: 'scene',
              scenario: 'scene',
              director: const RoleplayDirector(),
              participants: const [
                RoleplayParticipant(
                  id: 'player',
                  name: '我',
                  systemPrompt: '',
                  isPlayer: true,
                ),
              ],
              playerParticipantId: 'player',
              messages: [
                RoleplayMessage(
                  id: 'rm1',
                  speakerId: 'player',
                  speakerName: '我',
                  content: '',
                  kind: RoleplayMessageKind.player,
                  attachments: [
                    MessageImage(
                      path: roleplayAttachment.path,
                      name: 'role.txt',
                      size: 3,
                      mimeType: 'text/plain',
                    ),
                  ],
                  timestamp: now,
                ),
              ],
              createdAt: now,
              updatedAt: now,
            ),
          ],
        );

        final migrated =
            await LegacyResourceMigrationService(
              legacyRoot: legacyRoot,
              targetRoot: targetRoot,
            ).migrate(
              settingsProvider: settingsProvider,
              conversationProvider: conversationProvider,
              roleplayProvider: roleplayProvider,
            );

        expect(migrated, 3);
        expect(
          settingsProvider.settings.backgroundImagePath,
          '${targetRoot.path}/backgrounds/bg.png',
        );
        expect(
          conversationProvider
              .conversations
              .single
              .messages
              .single
              .images
              .single
              .path,
          '${targetRoot.path}/message_images/chat.png',
        );
        expect(
          roleplayProvider
              .threads
              .single
              .messages
              .single
              .attachments
              .single
              .path,
          '${targetRoot.path}/roleplay_attachments/role.txt',
        );
        expect(
          await File('${targetRoot.path}/backgrounds/bg.png').exists(),
          isTrue,
        );
        expect(await background.exists(), isTrue);
      } finally {
        await legacyRoot.delete(recursive: true);
        await targetRoot.delete(recursive: true);
      }
    },
  );

  test(
    'LegacyResourceMigrationService reuses identical copied targets',
    () async {
      SharedPreferences.setMockInitialValues({});
      final legacyRoot = await Directory.systemTemp.createTemp(
        'lynai_legacy_resources_',
      );
      final targetRoot = await Directory.systemTemp.createTemp(
        'lynai_target_resources_',
      );
      try {
        final source = await _writeFile(legacyRoot, 'backgrounds/bg.png', [
          1,
          2,
        ]);
        await _writeFile(targetRoot, 'backgrounds/bg.png', [1, 2]);

        final settingsProvider = SettingsProvider();
        final conversationProvider = ConversationProvider();
        final roleplayProvider = RoleplayProvider();
        await settingsProvider.replaceSettings(
          AppSettings.defaults().copyWith(backgroundImagePath: source.path),
        );

        final migrated =
            await LegacyResourceMigrationService(
              legacyRoot: legacyRoot,
              targetRoot: targetRoot,
            ).migrate(
              settingsProvider: settingsProvider,
              conversationProvider: conversationProvider,
              roleplayProvider: roleplayProvider,
            );

        expect(migrated, 1);
        expect(
          settingsProvider.settings.backgroundImagePath,
          '${targetRoot.path}/backgrounds/bg.png',
        );
        expect(
          await File('${targetRoot.path}/backgrounds/bg_1.png').exists(),
          isFalse,
        );
      } finally {
        await legacyRoot.delete(recursive: true);
        await targetRoot.delete(recursive: true);
      }
    },
  );

  test('LegacyResourceMigrationService skips missing old resources', () async {
    SharedPreferences.setMockInitialValues({});
    final legacyRoot = await Directory.systemTemp.createTemp(
      'lynai_legacy_resources_',
    );
    final targetRoot = await Directory.systemTemp.createTemp(
      'lynai_target_resources_',
    );
    try {
      final missing = '${legacyRoot.path}/backgrounds/missing.png';
      final settingsProvider = SettingsProvider();
      final conversationProvider = ConversationProvider();
      final roleplayProvider = RoleplayProvider();
      await settingsProvider.replaceSettings(
        AppSettings.defaults().copyWith(backgroundImagePath: missing),
      );

      final migrated =
          await LegacyResourceMigrationService(
            legacyRoot: legacyRoot,
            targetRoot: targetRoot,
          ).migrate(
            settingsProvider: settingsProvider,
            conversationProvider: conversationProvider,
            roleplayProvider: roleplayProvider,
          );

      expect(migrated, 0);
      expect(settingsProvider.settings.backgroundImagePath, missing);
    } finally {
      await legacyRoot.delete(recursive: true);
      await targetRoot.delete(recursive: true);
    }
  });
}

Future<File> _writeFile(
  Directory root,
  String relativePath,
  List<int> bytes,
) async {
  final file = File('${root.path}/$relativePath');
  if (!await file.parent.exists()) await file.parent.create(recursive: true);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}
