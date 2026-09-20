import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/roleplay.dart';

void main() {
  group('RoleplayThread.preview', () {
    test('显示最近一条玩家消息，而不是最早一条', () {
      final thread = _thread([
        _message('m1', RoleplayMessageKind.player, '开场白'),
        _message('m2', RoleplayMessageKind.character, '角色回应'),
        _message('m3', RoleplayMessageKind.player, '最新提问'),
      ]);

      expect(thread.preview, '最新提问');
    });

    test('没有玩家消息时回退到最后一条消息', () {
      final thread = _thread([
        _message('m1', RoleplayMessageKind.character, '角色开场'),
        _message('m2', RoleplayMessageKind.character, '角色补充'),
      ]);

      expect(thread.preview, '角色补充');
    });

    test('玩家消息只有附件时显示附件名', () {
      final thread = _thread([
        _message('m1', RoleplayMessageKind.player, '正文'),
        _message(
          'm2',
          RoleplayMessageKind.player,
          '',
          attachments: const [
            MessageImage(path: '/tmp/scene.png', name: 'scene.png', size: 4),
          ],
        ),
      ]);

      expect(thread.preview, '[附件] scene.png');
    });
  });
}

RoleplayMessage _message(
  String id,
  RoleplayMessageKind kind,
  String content, {
  List<MessageImage> attachments = const [],
}) {
  return RoleplayMessage(
    id: id,
    speakerId: kind == RoleplayMessageKind.player ? 'player' : 'npc',
    speakerName: kind == RoleplayMessageKind.player ? '玩家' : '角色',
    content: content,
    kind: kind,
    attachments: attachments,
    timestamp: DateTime.utc(2026, 1, 1),
  );
}

RoleplayThread _thread(List<RoleplayMessage> messages) {
  return RoleplayThread(
    id: 'thread-1',
    scenarioId: 'scenario-1',
    title: '标题',
    scenarioTitle: '情景',
    scenario: '开场设定',
    director: const RoleplayDirector(name: '导演'),
    participants: const [],
    playerParticipantId: 'player',
    messages: messages,
    createdAt: DateTime.utc(2026, 1, 1),
    updatedAt: DateTime.utc(2026, 1, 1),
  );
}
