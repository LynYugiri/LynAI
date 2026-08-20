import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/chat_quick_action.dart';

void main() {
  test('ChatQuickActions defaults point to schedule notes todos', () {
    final actions = ChatQuickActions.defaults();
    expect(actions.left.type, ChatQuickAction.typeFeaturePage);
    expect(actions.left.featureId, 'schedule');
    expect(actions.up.featureId, 'notes');
    expect(actions.right.featureId, 'todos');
  });

  test('ChatQuickActions round-trip through JSON', () {
    final actions = ChatQuickActions(
      left: ChatQuickAction.featurePage('knowledge'),
      up: const ChatQuickAction(type: ChatQuickAction.typeNewConversation),
      right: const ChatQuickAction(type: ChatQuickAction.typeSettings),
    );
    final restored = ChatQuickActions.fromJson(
      jsonDecode(jsonEncode(actions.toJson())) as Map<String, dynamic>,
    );
    expect(restored.left.featureId, 'knowledge');
    expect(restored.up.type, ChatQuickAction.typeNewConversation);
    expect(restored.right.type, ChatQuickAction.typeSettings);
  });

  test('ChatQuickAction falls back to dashboard for invalid feature', () {
    final action = ChatQuickAction.fromJson(const {
      'type': ChatQuickAction.typeFeaturePage,
      'featureId': 'not-a-page',
    });
    expect(action.featureId, 'dashboard');
  });

  test('AppSettings round-trips chatQuickActions', () {
    final settings = AppSettings.defaults().copyWith(
      chatQuickActions: ChatQuickActions(
        left: ChatQuickAction.featurePage('cards'),
        up: const ChatQuickAction(type: ChatQuickAction.typeNewConversation),
        right: ChatQuickAction.featurePage('jottings'),
      ),
    );
    final restored = AppSettings.fromJson(settings.toJson());
    expect(restored.chatQuickActions.left.featureId, 'cards');
    expect(
      restored.chatQuickActions.up.type,
      ChatQuickAction.typeNewConversation,
    );
    expect(restored.chatQuickActions.right.featureId, 'jottings');
  });
}
