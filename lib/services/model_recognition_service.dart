import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import '../models/conversation.dart';
import '../models/message.dart';
import '../models/model_config.dart';
import '../models/ocr_text_block.dart';
import '../providers/model_config_provider.dart';
import 'api_service.dart';
import 'device_control_service.dart';

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
    if (id == ModelConfig.localOcrId) {
      return _recognizeImagesOnDevice(files);
    }
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

  Future<List<OcrRecognitionResult>> recognizeImageBlocksWithOcr({
    required ModelConfigProvider modelConfigs,
    required String? modelId,
    required List<ModelRecognitionFileInput> files,
  }) async {
    if (files.isEmpty) return const [];
    final id = modelId?.trim();
    if (id == ModelConfig.localOcrId) {
      return _recognizeImageBlocksOnDevice(files);
    }
    if (id == null || id.isEmpty) throw Exception('请先选择 OCR 模型');
    final model = findModelConfigById(modelConfigs.models, id);
    if (model == null) throw Exception('OCR 模型已不存在，请在设置中重新选择');
    final results = <OcrRecognitionResult>[];
    for (final file in files.where(
      (item) => item.mimeType.startsWith('image/'),
    )) {
      results.add(await _api.recognizeImageTextBlocks(model, file.bytes));
    }
    return results;
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
      modelConfigs.enabledModelsByCategory(ModelConfig.categoryChat),
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

  // ── On-device OCR (ncnn + PPOCRv5) ──────────────────────────────────

  /// 对每张图片调用 `device.screen.ocr`（Android 端 ncnn + PPOCRv5），
  /// 返回拼接后的纯文本（与云端 OCR 路径格式一致）。
  Future<String> _recognizeImagesOnDevice(
    List<ModelRecognitionFileInput> files,
  ) async {
    final results = <String>[];
    for (final file in files.where((f) => f.mimeType.startsWith('image/'))) {
      try {
        final res = await DeviceControlService.instance.execute(
          'device.screen.ocr',
          {'imageBase64': base64Encode(file.bytes)},
        );
        if (res['ok'] == true) {
          final blocks = (res['result'] as List?) ?? const [];
          final text = blocks
              .cast<Map>()
              .map((b) => b['text']?.toString() ?? '')
              .where((t) => t.isNotEmpty)
              .join('\n');
          if (text.trim().isNotEmpty) results.add(text.trim());
        } else {
          final err = res['error'];
          final msg = err is Map
              ? err['message']?.toString() ?? '未知错误'
              : '未知错误';
          results.add('[${file.name} OCR 识别失败: $msg]');
        }
      } catch (e) {
        results.add('[${file.name} OCR 识别失败: $e]');
      }
    }
    return results.join('\n');
  }

  /// 返回结构化的本地 OCR 结果（含文本块和坐标）。
  Future<List<OcrRecognitionResult>> _recognizeImageBlocksOnDevice(
    List<ModelRecognitionFileInput> files,
  ) async {
    final results = <OcrRecognitionResult>[];
    for (final file in files.where((f) => f.mimeType.startsWith('image/'))) {
      try {
        final res = await DeviceControlService.instance.execute(
          'device.screen.ocr',
          {'imageBase64': base64Encode(file.bytes)},
        );
        if (res['ok'] == true) {
          final blocks = (res['result'] as List?) ?? const [];
          final textBlocks = <OcrTextBlock>[];
          for (var i = 0; i < blocks.length; i++) {
            final b = blocks[i];
            if (b is! Map) continue;
            final text = b['text']?.toString().trim() ?? '';
            if (text.isEmpty) continue;
            final bounds = b['bounds'];
            Rect? rect;
            if (bounds is Map) {
              final l = (bounds['left'] as num?)?.toDouble();
              final t = (bounds['top'] as num?)?.toDouble();
              final r = (bounds['right'] as num?)?.toDouble();
              final bo = (bounds['bottom'] as num?)?.toDouble();
              if (l != null && t != null && r != null && bo != null) {
                rect = Rect.fromLTRB(l, t, r, bo);
              }
            }
            textBlocks.add(
              OcrTextBlock(
                id: 'ocr_$i',
                text: text,
                bounds: rect,
                polygon: const [],
                confidence: (b['prob'] as num?)?.toDouble(),
                orientation: b['orientation'] == 1
                    ? OcrTextOrientation.vertical
                    : OcrTextOrientation.horizontal,
              ),
            );
          }
          results.add(
            OcrRecognitionResult(
              angle: 0,
              imageWidth: 0,
              imageHeight: 0,
              blocks: textBlocks,
            ),
          );
        }
      } catch (e) {
        // 跳过单张图片失败，但至少记录第一条错误
        if (results.isEmpty) {
          results.add(
            OcrRecognitionResult(
              angle: 0,
              imageWidth: 0,
              imageHeight: 0,
              blocks: [
                OcrTextBlock(
                  id: 'error',
                  text: '[${file.name} OCR 识别失败: $e]',
                  bounds: null,
                  polygon: const [],
                  orientation: OcrTextOrientation.unknown,
                ),
              ],
            ),
          );
        }
      }
    }
    return results;
  }

  static ModelConfig? findModelConfigById(List<ModelConfig> models, String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }
}
