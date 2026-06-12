import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';
import 'api_service.dart';

class ModelRecognitionFileInput {
  final String name;
  final String mimeType;
  final Uint8List bytes;

  const ModelRecognitionFileInput({
    required this.name,
    required this.mimeType,
    required this.bytes,
  });

  factory ModelRecognitionFileInput.fromBase64({
    required String name,
    required String mimeType,
    required String dataBase64,
  }) {
    return ModelRecognitionFileInput(
      name: name,
      mimeType: mimeType,
      bytes: base64Decode(dataBase64),
    );
  }

  static Future<ModelRecognitionFileInput> fromMessageImage(
    MessageImage file,
  ) async {
    return ModelRecognitionFileInput(
      name: file.name,
      mimeType: file.mimeType,
      bytes: await File(file.path).readAsBytes(),
    );
  }

  ChatFileInput toChatFileInput() {
    return ChatFileInput(bytes: bytes, mimeType: mimeType, name: name);
  }
}

class ModelRecognitionService {
  final ApiService _api;
  final bool _ownsApi;

  ModelRecognitionService({ApiService? api})
    : _api = api ?? ApiService(),
      _ownsApi = api == null;

  void dispose() {
    if (_ownsApi) _api.dispose();
  }

  Future<String> recognizeImagesWithOcr({
    required ModelConfigProvider modelConfigs,
    required String? modelId,
    required List<ModelRecognitionFileInput> files,
  }) async {
    if (files.isEmpty) return '';
    final id = modelId?.trim();
    if (id == null || id.isEmpty) throw Exception('请先选择 OCR 模型');
    final model = findModelConfigById(modelConfigs.models, id);
    if (model == null) throw Exception('OCR 模型已不存在，请在设置中重新选择');
    final results = <String>[];
    for (final file in files.where(
      (item) => item.mimeType.startsWith('image/'),
    )) {
      try {
        final text = await _api.recognizeImageText(model, file.bytes);
        final clean = text.trim();
        if (clean.isNotEmpty) results.add(clean);
      } catch (e) {
        results.add('[${file.name} OCR 识别失败: $e]');
      }
    }
    return results.join('\n');
  }

  Future<String> recognizeFilesWithModel({
    required ModelConfigProvider modelConfigs,
    required String? modelId,
    required String prompt,
    required List<ModelRecognitionFileInput> files,
  }) async {
    if (files.isEmpty) return '';
    final id = modelId?.trim();
    if (id == null || id.isEmpty) throw Exception('请先选择文件识别模型');
    final model = findModelConfigById(
      modelConfigs.modelsByCategory(ModelConfig.categoryChat),
      id,
    );
    if (model == null) throw Exception('文件识别模型已不存在，请在设置中重新选择');
    if (!model.supportsVision) {
      throw Exception('当前文件识别模型未开启视觉能力，请在模型设置中启用');
    }
    return _api.recognizeImageTextWithChatModel(
      model,
      prompt,
      files.map((file) => file.toChatFileInput()).toList(growable: false),
    );
  }

  Future<String> recognizeMessageImagesWithOcr({
    required ModelConfigProvider modelConfigs,
    required ConversationSettings settings,
    required List<MessageImage> files,
  }) async {
    return recognizeImagesWithOcr(
      modelConfigs: modelConfigs,
      modelId: settings.imageModelId,
      files: await _messageInputs(files.where((file) => file.isImage)),
    );
  }

  Future<String> recognizeMessageFilesWithModel({
    required ModelConfigProvider modelConfigs,
    required ConversationSettings settings,
    required List<MessageImage> files,
  }) async {
    return recognizeFilesWithModel(
      modelConfigs: modelConfigs,
      modelId: settings.imageRecognitionModelId,
      prompt: settings.imageRecognitionPrompt,
      files: await _messageInputs(files),
    );
  }

  Future<List<ModelRecognitionFileInput>> _messageInputs(
    Iterable<MessageImage> files,
  ) async {
    final inputs = <ModelRecognitionFileInput>[];
    for (final file in files) {
      inputs.add(await ModelRecognitionFileInput.fromMessageImage(file));
    }
    return inputs;
  }

  static ModelConfig? findModelConfigById(List<ModelConfig> models, String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}
