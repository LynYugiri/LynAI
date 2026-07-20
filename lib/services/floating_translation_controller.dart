import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/model_config.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import 'api_service.dart';
import 'backend_client.dart';
import 'floating_assistant_bridge.dart';

typedef TranslationStreamRequest =
    Stream<StreamChunk> Function(
      ModelConfig model,
      List<Map<String, dynamic>> messages,
    );
typedef CaptureOcrGroups = Future<List<Map<String, dynamic>>> Function();
typedef ReplaceTranslations =
    Future<void> Function(Map<String, dynamic> payload);
typedef ClearTranslations = Future<void> Function();

class FloatingTranslationController extends ChangeNotifier {
  FloatingTranslationController({
    required SettingsProvider settings,
    required ModelConfigProvider models,
    BackendClient? backend,
    TranslationStreamRequest? sendStreamRequest,
    CaptureOcrGroups? captureOcrGroups,
    ReplaceTranslations? replaceTranslations,
    ClearTranslations? clearTranslations,
  }) : _settings = settings,
       _models = models,
       _captureOcrGroups =
           captureOcrGroups ??
           FloatingAssistantBridge.instance.captureOcrGroups,
       _replaceTranslations =
           replaceTranslations ??
           FloatingAssistantBridge.instance.replaceTranslations,
       _clearTranslations =
           clearTranslations ??
           FloatingAssistantBridge.instance.clearTranslations {
    final api = ApiService(backend: backend);
    _api = api;
    _sendStreamRequest =
        sendStreamRequest ??
        (model, messages) =>
            api.sendStreamRequest(model, messages, thinking: false);
  }

  static const _translationHistoryKey = 'floating_translation_history';
  static const _maxHistoryEntries = 20;
  static const _maxBlocks = 30;

  static const _languageNames = <String, String>{
    'zh-CN': '简体中文',
    'zh-TW': '繁體中文',
    'en': 'English',
    'ja': '日本語',
    'ko': '한국어',
    'fr': 'Français',
    'de': 'Deutsch',
    'es': 'Español',
    'ru': 'Русский',
    'pt': 'Português',
    'it': 'Italiano',
    'th': 'ไทย',
    'vi': 'Tiếng Việt',
    'ar': 'العربية',
  };

  final SettingsProvider _settings;
  final ModelConfigProvider _models;
  late final ApiService _api;
  late final TranslationStreamRequest _sendStreamRequest;
  final CaptureOcrGroups _captureOcrGroups;
  final ReplaceTranslations _replaceTranslations;
  final ClearTranslations _clearTranslations;

  final List<Map<String, dynamic>> _history = [];
  List<Map<String, dynamic>> _translations = const [];
  StreamSubscription<StreamChunk>? _subscription;
  int _requestId = 0;
  bool _automatic = false;
  bool _translating = false;
  bool _scrolling = false;
  String _status = '';
  String _error = '';

  bool get isAutomatic => _automatic;
  bool get isTranslating => _translating;
  String get status => _status;
  String get error => _error;
  String get translationText => _translations
      .map((block) => block['translatedText']?.toString() ?? '')
      .where((text) => text.isNotEmpty)
      .join('\n');
  List<Map<String, dynamic>> get translations =>
      List.unmodifiable(_translations);
  List<Map<String, dynamic>> get translationHistory =>
      List.unmodifiable(_history);

  @visibleForTesting
  int get requestId => _requestId;

  Future<void> translateManually() async {
    _automatic = false;
    await _translateCapturedScreen();
  }

  Future<void> startAutomatic() async {
    if (_automatic) return;
    _automatic = true;
    notifyListeners();
    await _translateCapturedScreen();
  }

  Future<void> stopAutomatic() async {
    _automatic = false;
    _scrolling = false;
    final wasTranslating = _translating;
    await _cancelRequest();
    if (wasTranslating) await _restoreCurrentTranslations();
    _status = _translations.isEmpty ? '已停止自动翻译' : '已停止自动翻译，保留当前译文';
    notifyListeners();
  }

  Future<void> clear() async {
    _automatic = false;
    _scrolling = false;
    await _cancelRequest();
    _translations = const [];
    _status = '';
    _error = '';
    await _clearTranslations();
    notifyListeners();
  }

  Future<void> onScrollStarted() async {
    if (!_automatic) return;
    _scrolling = true;
    final wasTranslating = _translating;
    await _cancelRequest();
    if (wasTranslating) await _restoreCurrentTranslations();
    _status = '滚动中，已保留当前译文';
    notifyListeners();
  }

  Future<void> onScrollSettled() async {
    if (!_automatic || !_scrolling) return;
    _scrolling = false;
    await _translateCapturedScreen();
  }

  Future<void> _translateCapturedScreen() async {
    await _cancelRequest();
    final requestId = ++_requestId;
    await _clearTranslations();
    if (requestId != _requestId) return;
    _error = '';
    _status = '正在读取当前页面...';
    _translating = true;
    notifyListeners();

    try {
      final groups = await _captureOcrGroups();
      if (requestId != _requestId) return;
      final blocks = _normalizeGroups(groups).take(_maxBlocks).toList();
      if (blocks.isEmpty) {
        await _finishWithError(requestId, '当前页面没有可读取文本');
        return;
      }
      final model = _translationModel();
      if (model == null) {
        await _finishWithError(requestId, '请先在设置中添加 AI 模型');
        return;
      }
      final targetLanguage =
          _languageNames[_settings
              .settings
              .floatingAssistant
              .mangaTargetLanguage] ??
          '简体中文';
      final packageName = blocks.first['packageName']?.toString() ?? '';
      final messages = <Map<String, dynamic>>[
        {
          'role': 'system',
          'content': buildTranslationPrompt(targetLanguage, packageName),
        },
        {'role': 'user', 'content': buildTranslationInput(blocks)},
      ];
      var response = '';
      _status = '正在翻译 ${blocks.length} 段...';
      notifyListeners();
      _subscription = _sendStreamRequest(model, messages).listen(
        (chunk) {
          if (requestId != _requestId) return;
          if (chunk.content != null) response += chunk.content!;
        },
        onError: (Object exception) {
          if (requestId != _requestId) return;
          _subscription = null;
          unawaited(_finishWithError(requestId, '翻译失败: $exception'));
        },
        onDone: () {
          if (requestId != _requestId) return;
          _subscription = null;
          unawaited(_applyResponse(requestId, response, blocks));
        },
      );
    } catch (exception) {
      await _finishWithError(requestId, '翻译失败: $exception');
    }
  }

  Future<void> _applyResponse(
    int requestId,
    String response,
    List<Map<String, dynamic>> blocks,
  ) async {
    final mapped = parseTranslations(response, blocks);
    if (requestId != _requestId) return;
    final translated = blocks
        .where((block) => mapped.containsKey(block['id']))
        .map(
          (block) => <String, dynamic>{
            ...block,
            'translatedText': mapped[block['id']]!,
          },
        )
        .toList(growable: false);
    final floating = _settings.settings.floatingAssistant;
    await _replaceTranslations({
      'blocks': translated,
      'style': floating.mangaOverlayStyle,
      'opacity': floating.mangaOverlayOpacity,
      'layoutMode': floating.mangaLayoutMode,
      'targetLanguage': floating.mangaTargetLanguage,
    });
    if (requestId != _requestId) return;
    _translations = translated;
    _translating = false;
    _status = translated.isEmpty
        ? '未获得译文'
        : '已翻译 ${translated.length}/${blocks.length} 段';
    if (!_automatic) await _saveToHistory(translated);
    notifyListeners();
  }

  Future<void> _cancelRequest() async {
    _requestId++;
    final subscription = _subscription;
    _subscription = null;
    _translating = false;
    await subscription?.cancel();
  }

  Future<void> _finishWithError(int requestId, String message) async {
    if (requestId != _requestId) return;
    await _restoreCurrentTranslations();
    if (requestId != _requestId) return;
    _translating = false;
    _error = message;
    _status = '';
    notifyListeners();
  }

  Future<void> _restoreCurrentTranslations() async {
    if (_translations.isEmpty) return;
    final floating = _settings.settings.floatingAssistant;
    await _replaceTranslations({
      'blocks': _translations,
      'style': floating.mangaOverlayStyle,
      'opacity': floating.mangaOverlayOpacity,
      'layoutMode': floating.mangaLayoutMode,
      'targetLanguage': floating.mangaTargetLanguage,
    });
  }

  Iterable<Map<String, dynamic>> _normalizeGroups(
    List<Map<String, dynamic>> groups,
  ) sync* {
    final blocked = _settings.settings.floatingAssistant.blockedPackages;
    for (final group in groups) {
      final packageName = group['packageName']?.toString() ?? '';
      if (packageName.isNotEmpty && blocked.contains(packageName)) continue;
      final block = normalizeOcrBlock(group, packageName);
      if (block != null) yield block;
    }
  }

  ModelConfig? _translationModel() {
    final configuredId =
        _settings.settings.floatingAssistant.translationModelId;
    if (configuredId != null && configuredId.isNotEmpty) {
      final configured = _findModel(_models.models, configuredId);
      if (configured != null) return configured;
    }
    final chatModels = _models.enabledModelsByCategory(
      ModelConfig.categoryChat,
    );
    if (chatModels.isEmpty) return null;
    final role = _settings.currentRole;
    final roleModelId = role.modelId;
    if (roleModelId != null && roleModelId.isNotEmpty) {
      final model = _findModel(chatModels, roleModelId);
      if (model != null) {
        return role.modelName == null || role.modelName!.isEmpty
            ? model
            : model.copyWith(modelName: role.modelName);
      }
    }
    final lastModelId = _settings.settings.lastChatModelId;
    if (lastModelId != null && lastModelId.isNotEmpty) {
      final model = _findModel(chatModels, lastModelId);
      if (model != null) return model;
    }
    return chatModels.first;
  }

  ModelConfig? _findModel(List<ModelConfig> models, String id) {
    for (final model in models) {
      if (model.id == id) return model;
    }
    return null;
  }

  @visibleForTesting
  static String buildTranslationPrompt(
    String targetLanguage,
    String packageName,
  ) {
    final contextHint = packageName.isEmpty ? '' : '当前页面来自应用: $packageName。';
    return '你是屏幕文本翻译助手。$contextHint'
        '将输入 JSON 数组中每个对象的 text 翻译成$targetLanguage。'
        '如果文本已经是$targetLanguage，则原样返回。'
        '严格返回 JSON 数组，每个元素只包含原始 "id" 和对应的 "translation"。'
        '不得修改 id，不要合并或拆分文本块，不要输出 JSON 之外的内容。';
  }

  @visibleForTesting
  static String buildTranslationInput(List<Map<String, dynamic>> blocks) {
    return jsonEncode(
      blocks
          .map(
            (block) => {
              'id': block['id']?.toString() ?? '',
              'text': block['originalText']?.toString() ?? '',
            },
          )
          .toList(growable: false),
    );
  }

  @visibleForTesting
  static Map<String, String> parseTranslations(
    String response,
    List<Map<String, dynamic>> blocks,
  ) {
    final validIds = blocks
        .map((block) => block['id']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    final result = <String, String>{};
    try {
      var json = response.trim();
      if (json.startsWith('```')) {
        json = json
            .replaceAll(RegExp(r'^```(?:json)?\n?'), '')
            .replaceAll(RegExp(r'\n?```$'), '');
      }
      final parsed = jsonDecode(json);
      if (parsed is! List) return result;
      for (final item in parsed.whereType<Map>()) {
        final id = item['id']?.toString() ?? '';
        final translation = item['translation']?.toString().trim() ?? '';
        if (validIds.contains(id) && translation.isNotEmpty) {
          result[id] = translation;
        }
      }
    } catch (_) {
      return result;
    }
    return result;
  }

  @visibleForTesting
  static Map<String, dynamic>? normalizeOcrBlock(
    Map<String, dynamic> raw,
    String packageName,
  ) {
    final text = (raw['text'] ?? raw['originalText'])?.toString().trim() ?? '';
    if (text.isEmpty || isLikelyUiLabel(text)) return null;
    final bounds =
        (raw['displayBounds'] as Map?) ?? (raw['bounds'] as Map?) ?? const {};
    final left = (bounds['left'] as num?)?.toInt() ?? 0;
    final top = (bounds['top'] as num?)?.toInt() ?? 0;
    final right = (bounds['right'] as num?)?.toInt() ?? 0;
    final bottom = (bounds['bottom'] as num?)?.toInt() ?? 0;
    final id = raw['id']?.toString().trim();
    return <String, dynamic>{
      'id': id == null || id.isEmpty
          ? blockId(text, left, top, right, bottom)
          : id,
      'originalText': text,
      'bounds': {'left': left, 'top': top, 'right': right, 'bottom': bottom},
      if (raw['displayBounds'] is Map)
        'displayBounds': Map<String, dynamic>.from(
          (raw['displayBounds'] as Map).cast<String, dynamic>(),
        ),
      if (raw['polygon'] is List) 'polygon': raw['polygon'],
      'orientation': raw['orientation'] ?? 0,
      'boxW': (raw['boxW'] as num?)?.toInt() ?? 0,
      'boxH': (raw['boxH'] as num?)?.toInt() ?? 0,
      'fontSize':
          (raw['fontSize'] as num?)?.toDouble() ??
          (raw['fontSizePx'] as num?)?.toDouble() ??
          0.0,
      'angle': (raw['angle'] as num?)?.toDouble() ?? 0.0,
      'confidence': (raw['confidence'] as num?)?.toDouble() ?? 0.0,
      'packageName': packageName,
    };
  }

  @visibleForTesting
  static String blockId(
    String text,
    int left,
    int top,
    int right,
    int bottom,
  ) => '$text|${left ~/ 8},${top ~/ 8},${right ~/ 8},${bottom ~/ 8}';

  @visibleForTesting
  static bool isLikelyUiLabel(String text) {
    if (text.isEmpty) return true;
    const labels = {
      '确定',
      '取消',
      '返回',
      '关闭',
      '搜索',
      '更多',
      '设置',
      '分享',
      '编辑',
      '删除',
      'OK',
      'ok',
    };
    if (labels.contains(text)) return true;
    if (text.length == 1) return RegExp(r'^[A-Za-z0-9]$').hasMatch(text);
    return text.length == 2 && RegExp(r'^[A-Za-z0-9]+$').hasMatch(text);
  }

  Future<void> _saveToHistory(List<Map<String, dynamic>> blocks) async {
    if (blocks.isEmpty) return;
    _history.insert(0, {
      'timestamp': DateTime.now().millisecondsSinceEpoch,
      'originalText': blocks
          .map((block) => block['originalText']?.toString() ?? '')
          .join(' | '),
      'translatedText': blocks
          .map((block) => block['translatedText']?.toString() ?? '')
          .join(' | '),
      'packageName': blocks.first['packageName']?.toString() ?? '',
    });
    if (_history.length > _maxHistoryEntries) {
      _history.removeRange(_maxHistoryEntries, _history.length);
    }
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_translationHistoryKey, jsonEncode(_history));
    } catch (exception) {
      debugPrint('Failed to save translation history: $exception');
    }
  }

  Future<void> loadTranslationHistory() async {
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_translationHistoryKey);
      if (raw == null) return;
      final decoded = jsonDecode(raw);
      if (decoded is! List) return;
      _history
        ..clear()
        ..addAll(decoded.whereType<Map>().map(Map<String, dynamic>.from));
      notifyListeners();
    } catch (exception) {
      debugPrint('Failed to load translation history: $exception');
    }
  }

  Future<void> clearTranslationHistory() async {
    _history.clear();
    notifyListeners();
    if (!Platform.isAndroid) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove(_translationHistoryKey);
    } catch (exception) {
      debugPrint('Failed to clear translation history: $exception');
    }
  }

  @override
  Future<void> dispose() async {
    await _cancelRequest();
    _api.dispose();
    super.dispose();
  }
}
