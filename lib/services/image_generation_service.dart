import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../models/message.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';
import 'api_service.dart';
import 'attachment_storage_service.dart';

class ImageGenerationResult {
  final ModelConfig model;
  final List<MessageImage> images;

  const ImageGenerationResult({required this.model, required this.images});
}

class ImageGenerationService {
  ImageGenerationService({
    ApiService? api,
    AttachmentStorageService attachmentStorage =
        const AttachmentStorageService(),
    http.Client? httpClient,
  }) : _api = api ?? ApiService(),
       _ownsApi = api == null,
       _attachmentStorage = attachmentStorage,
       _httpClient = httpClient ?? http.Client(),
       _ownsHttpClient = httpClient == null;

  final ApiService _api;
  final bool _ownsApi;
  final AttachmentStorageService _attachmentStorage;
  final http.Client _httpClient;
  final bool _ownsHttpClient;

  Future<ImageGenerationResult> generate({
    required ModelConfigProvider modelConfigs,
    required String prompt,
    String? modelId,
    String? modelName,
    Map<String, dynamic>? parameters,
  }) async {
    final cleanPrompt = prompt.trim();
    if (cleanPrompt.isEmpty) throw Exception('图片生成缺少 prompt');
    final model = _selectImageModel(modelConfigs, modelId, modelName);
    final normalizedParameters = _normalizeParameters(parameters);
    final results = await _api.generateImages(
      model,
      cleanPrompt,
      parameters: normalizedParameters,
    );
    if (results.isEmpty) throw Exception('图片生成没有返回图片');
    final images = <MessageImage>[];
    for (var i = 0; i < results.length; i++) {
      final bytes = await _bytesFromResult(results[i]);
      final stored = await _attachmentStorage.storeBytes(
        bytes,
        directoryName: 'message_images',
        name: _imageName(i, _mimeTypeFromBytes(bytes)),
        fallbackName: 'generated_image',
        mimeType: _mimeTypeFromBytes(bytes),
      );
      images.add(
        MessageImage(
          path: stored.path,
          name: stored.name,
          size: stored.size,
          mimeType: stored.mimeType,
        ),
      );
    }
    return ImageGenerationResult(model: model, images: images);
  }

  void dispose() {
    if (_ownsApi) _api.dispose();
    if (_ownsHttpClient) _httpClient.close();
  }

  ModelConfig _selectImageModel(
    ModelConfigProvider provider,
    String? modelId,
    String? modelName,
  ) {
    final models = provider.modelsByCategory(
      ModelConfig.categoryImageGeneration,
    );
    if (models.isEmpty) throw Exception('没有可用图片生成模型');
    final id = modelId?.trim();
    if (id != null && id.isNotEmpty) {
      for (final model in models) {
        if (model.id == id) return _withRequestedModelName(model, modelName);
      }
      throw Exception('未找到图片生成模型: $id');
    }
    return _withRequestedModelName(models.first, modelName);
  }

  ModelConfig _withRequestedModelName(ModelConfig model, String? rawModelName) {
    final modelName = rawModelName?.trim();
    if (modelName == null ||
        modelName.isEmpty ||
        modelName == model.modelName) {
      return model;
    }
    for (final entry in model.models) {
      if (entry.name == modelName) {
        if (!entry.enabled) throw Exception('图片生成子模型未启用: $modelName');
        return model.copyWith(modelName: modelName);
      }
    }
    throw Exception('未找到图片生成子模型: $modelName');
  }

  Map<String, dynamic>? _normalizeParameters(Map<String, dynamic>? parameters) {
    if (parameters == null || parameters.isEmpty) {
      return {'response_format': 'b64_json'};
    }
    final normalized = Map<String, dynamic>.from(parameters);
    normalized.putIfAbsent('response_format', () => 'b64_json');
    return normalized;
  }

  Future<Uint8List> _bytesFromResult(String value) async {
    final trimmed = value.trim();
    if (trimmed.startsWith('http://') || trimmed.startsWith('https://')) {
      final response = await _httpClient.get(Uri.parse(trimmed));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception('下载生成图片失败: ${response.statusCode}');
      }
      return response.bodyBytes;
    }
    final comma = trimmed.indexOf(',');
    final payload = trimmed.startsWith('data:') && comma != -1
        ? trimmed.substring(comma + 1)
        : trimmed;
    try {
      return base64Decode(payload);
    } catch (e) {
      throw Exception('图片生成返回了无法识别的图片数据: $e');
    }
  }

  String _mimeTypeFromBytes(Uint8List bytes) {
    if (bytes.length >= 12 &&
        bytes[0] == 0x52 &&
        bytes[1] == 0x49 &&
        bytes[2] == 0x46 &&
        bytes[3] == 0x46 &&
        bytes[8] == 0x57 &&
        bytes[9] == 0x45 &&
        bytes[10] == 0x42 &&
        bytes[11] == 0x50) {
      return 'image/webp';
    }
    if (bytes.length >= 3 && bytes[0] == 0xff && bytes[1] == 0xd8) {
      return 'image/jpeg';
    }
    return 'image/png';
  }

  String _imageName(int index, String mimeType) {
    final extension = switch (mimeType) {
      'image/webp' => 'webp',
      'image/jpeg' => 'jpg',
      _ => 'png',
    };
    final suffix = index == 0 ? '' : '_${index + 1}';
    return 'generated_image$suffix.$extension';
  }
}
