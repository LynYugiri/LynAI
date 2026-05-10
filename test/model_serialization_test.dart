import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lynai/models/app_settings.dart';
import 'package:lynai/models/conversation.dart';
import 'package:lynai/models/message.dart';
import 'package:lynai/models/model_config.dart';

void main() {
  test('AppSettings preserves nullable fields through copyWith sentinel', () {
    final settings = AppSettings(
      themeColor: Colors.purple,
      speechModelId: 'speech-1',
      imageModelId: 'ocr-1',
      imageRecognitionModelId: 'vision-1',
      lastChatModelId: 'chat-1',
    );

    expect(settings.copyWith().speechModelId, 'speech-1');
    expect(settings.copyWith(speechModelId: null).speechModelId, isNull);
    expect(settings.copyWith(imageModelId: null).imageModelId, isNull);
    expect(
      settings.copyWith(imageRecognitionModelId: null).imageRecognitionModelId,
      isNull,
    );
    expect(settings.copyWith(lastChatModelId: null).lastChatModelId, isNull);
  });

  test('Message serializes image attachments', () {
    final message = Message(
      id: 'm1',
      role: 'user',
      content: 'hello',
      images: const [MessageImage(path: '/tmp/a.png', name: 'a.png', size: 12)],
      timestamp: DateTime.utc(2026),
    );

    final restored = Message.fromJson(message.toJson());

    expect(restored.images, hasLength(1));
    expect(restored.images.single.path, '/tmp/a.png');
    expect(restored.images.single.name, 'a.png');
    expect(restored.images.single.size, 12);
  });

  test('ConversationSettings reads legacy imagePrompt key', () {
    final settings = ConversationSettings.fromJson({
      'modelId': 'chat-1',
      'imagePrompt': 'legacy prompt',
    });

    expect(settings.imageRecognitionPrompt, 'legacy prompt');
  });

  test('ModelConfig defaults category and enabled model entry', () {
    final config = ModelConfig.fromJson({
      'id': '1',
      'name': 'Provider',
      'endpoint': 'https://example.com',
      'apiKey': 'key',
      'modelName': 'model-a',
      'apiType': 'openai',
      'priority': 0,
    });

    expect(config.category, ModelConfig.categoryChat);
    expect(config.enabledModelNames, ['model-a']);
  });
}
