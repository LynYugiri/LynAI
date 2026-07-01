import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/model_config.dart';
import '../providers/model_config_provider.dart';
import '../providers/settings_provider.dart';
import '../services/device_control_service.dart';
import '../services/floating_assistant_service.dart';
import '../widgets/text_editing_controller_host.dart';
import 'translation_history_page.dart';

class FloatingAssistantSettingsPage extends StatelessWidget {
  const FloatingAssistantSettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final settings = provider.settings.floatingAssistant;
    return Scaffold(
      appBar: AppBar(title: const Text('悬浮窗'), centerTitle: true),
      body: ListView(
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          if (!Platform.isAndroid) const _UnsupportedPlatformCard(),
          _section(
            context,
            '基础',
            children: [
              SwitchListTile(
                title: const Text('启用悬浮助手'),
                subtitle: const Text('仅 Android 支持系统级悬浮窗'),
                value: settings.enabled && Platform.isAndroid,
                onChanged: Platform.isAndroid
                    ? (value) =>
                          _update(context, settings.copyWith(enabled: value))
                    : null,
              ),
              SwitchListTile(
                title: const Text('后台显示悬浮球'),
                subtitle: const Text('LynAI 退到后台后显示可拖拽入口'),
                value: settings.showBubbleInBackground,
                onChanged: settings.enabled
                    ? (value) => _update(
                        context,
                        settings.copyWith(showBubbleInBackground: value),
                      )
                    : null,
              ),
              SwitchListTile(
                title: const Text('显示 Agent 任务面板'),
                subtitle: const Text('仅 Agent 执行时展示 Plan；暂停时才显示继续'),
                value: settings.showAgentPlan,
                onChanged: settings.enabled
                    ? (value) => _update(
                        context,
                        settings.copyWith(showAgentPlan: value),
                      )
                    : null,
              ),
            ],
          ),
          _section(
            context,
            '权限',
            children: [
              ListTile(
                leading: const Icon(Icons.layers_outlined),
                title: const Text('悬浮窗权限'),
                subtitle: const Text('允许 LynAI 在其他应用上方显示悬浮球和面板'),
                trailing: const Icon(Icons.open_in_new),
                enabled: Platform.isAndroid,
                onTap: Platform.isAndroid
                    ? () => _openDeviceSettings('overlay')
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.accessibility_new_outlined),
                title: const Text('无障碍服务'),
                subtitle: const Text('模型按需读取当前页面和屏幕翻译需要开启'),
                trailing: const Icon(Icons.open_in_new),
                enabled: Platform.isAndroid,
                onTap: Platform.isAndroid
                    ? () => _openDeviceSettings('accessibility')
                    : null,
              ),
            ],
          ),
          _section(
            context,
            '聊天',
            children: [
              SwitchListTile(
                title: const Text('允许模型按需读取当前页面'),
                subtitle: const Text('悬浮聊天中，模型只在问题依赖当前页面时调用读取接口'),
                value: settings.allowScreenContext,
                onChanged: settings.enabled
                    ? (value) => _update(
                        context,
                        settings.copyWith(allowScreenContext: value),
                      )
                    : null,
              ),
              _OptionTile(
                title: '页面内容附带方式',
                value: settings.screenContextMode,
                values: const {
                  FloatingAssistantSettings.screenContextManual: '手动附带',
                  FloatingAssistantSettings.screenContextDisabled: '关闭',
                },
                enabled: settings.enabled && settings.allowScreenContext,
                onChanged: (value) => _update(
                  context,
                  settings.copyWith(screenContextMode: value),
                ),
              ),
              _OptionTile(
                title: '语音输入',
                value: settings.voiceInputMode,
                values: const {
                  FloatingAssistantSettings.voiceInputSystem: '系统语音识别',
                  FloatingAssistantSettings.voiceInputServer: '服务端语音转文字',
                  FloatingAssistantSettings.voiceInputDisabled: '关闭',
                },
                enabled: settings.enabled,
                onChanged: (value) =>
                    _update(context, settings.copyWith(voiceInputMode: value)),
              ),
            ],
          ),
          _section(
            context,
            '翻译',
            children: [
              SwitchListTile(
                title: const Text('显示翻译按钮'),
                subtitle: const Text('在悬浮聊天中翻译当前屏幕可读取文本'),
                value: settings.showMangaTranslationAction,
                onChanged: settings.enabled
                    ? (value) => _update(
                        context,
                        settings.copyWith(showMangaTranslationAction: value),
                      )
                    : null,
              ),
              _OptionTile(
                title: '目标语言',
                value: settings.mangaTargetLanguage,
                values: const {
                  'zh-CN': '简体中文',
                  'zh-TW': '繁體中文',
                  'en': 'English',
                  'ja': '日本語',
                  'ko': '한국어',
                  'fr': 'Français',
                  'de': 'Deutsch',
                  'es': 'Español',
                  'ru': 'Русский',
                },
                enabled:
                    settings.enabled && settings.showMangaTranslationAction,
                onChanged: (value) => _update(
                  context,
                  settings.copyWith(mangaTargetLanguage: value),
                ),
              ),
              _OptionTile(
                title: '译文排版',
                value: settings.mangaLayoutMode,
                values: const {
                  FloatingAssistantSettings.mangaLayoutAuto: '自动',
                  FloatingAssistantSettings.mangaLayoutHorizontal: '横排优先',
                  FloatingAssistantSettings.mangaLayoutVertical: '竖排优先',
                },
                enabled:
                    settings.enabled && settings.showMangaTranslationAction,
                onChanged: (value) =>
                    _update(context, settings.copyWith(mangaLayoutMode: value)),
              ),
              _OptionTile(
                title: '覆盖风格',
                value: settings.mangaOverlayStyle,
                values: const {
                  FloatingAssistantSettings.mangaOverlayAuto: '自动拟合',
                  FloatingAssistantSettings.mangaOverlayLight: '白底黑字',
                  FloatingAssistantSettings.mangaOverlayDark: '黑底白字',
                  FloatingAssistantSettings.mangaOverlayStroke: '透明描边',
                },
                enabled:
                    settings.enabled && settings.showMangaTranslationAction,
                onChanged: (value) => _update(
                  context,
                  settings.copyWith(mangaOverlayStyle: value),
                ),
              ),
              ListTile(
                title: const Text('覆盖不透明度'),
                subtitle: Slider(
                  value: settings.mangaOverlayOpacity,
                  min: 0.2,
                  max: 1.0,
                  divisions: 8,
                  label: '${(settings.mangaOverlayOpacity * 100).round()}%',
                  onChanged:
                      settings.enabled && settings.showMangaTranslationAction
                      ? (value) => _update(
                          context,
                          settings.copyWith(mangaOverlayOpacity: value),
                        )
                      : null,
                ),
              ),
              _TranslationModelTile(settings),
              ListTile(
                leading: const Icon(Icons.block),
                title: const Text('屏蔽应用包名'),
                subtitle: Text(
                  settings.blockedPackages.isEmpty
                      ? '不屏蔽任何应用'
                      : '已屏蔽 ${settings.blockedPackages.length} 个应用',
                ),
                enabled:
                    Platform.isAndroid &&
                    settings.enabled &&
                    settings.showMangaTranslationAction,
                onTap: Platform.isAndroid
                    ? () => _editBlockedPackages(context, settings)
                    : null,
              ),
              ListTile(
                leading: const Icon(Icons.history),
                title: const Text('翻译历史'),
                subtitle: Text(
                  Platform.isAndroid ? '查看最近的屏幕翻译记录' : '仅 Android 可用',
                ),
                enabled: Platform.isAndroid,
                onTap: Platform.isAndroid ? () => _openHistory(context) : null,
              ),
            ],
          ),
          _section(
            context,
            '位置与尺寸',
            children: [
              ListTile(
                leading: const Icon(Icons.restart_alt),
                title: const Text('重置悬浮窗位置'),
                subtitle: const Text('清除记住的气泡和面板位置，恢复默认'),
                enabled: Platform.isAndroid,
                onTap: Platform.isAndroid
                    ? () => _update(
                        context,
                        settings.copyWith(
                          bubbleX: FloatingAssistantSettings.defaultPosition,
                          bubbleY: FloatingAssistantSettings.defaultPosition,
                          panelX: FloatingAssistantSettings.defaultPosition,
                          panelY: FloatingAssistantSettings.defaultPosition,
                          panelWidth: FloatingAssistantSettings.defaultPosition,
                          panelHeight:
                              FloatingAssistantSettings.defaultPosition,
                        ),
                      )
                    : null,
              ),
            ],
          ),
          _section(
            context,
            '隐私',
            children: const [
              ListTile(
                leading: Icon(Icons.privacy_tip_outlined),
                title: Text('页面内容和截图只在你主动触发时处理'),
                subtitle: Text('模型读取当前页面、语音转写和翻译可能会把内容发送给已配置的模型服务。'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  static Widget _section(
    BuildContext context,
    String title, {
    required List<Widget> children,
  }) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
            child: Text(
              title,
              style: Theme.of(
                context,
              ).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800),
            ),
          ),
          ...children,
        ],
      ),
    );
  }

  static void _update(
    BuildContext context,
    FloatingAssistantSettings settings,
  ) {
    context.read<SettingsProvider>().updateFloatingAssistant(settings);
  }

  static void _openDeviceSettings(String target) {
    DeviceControlService.instance.execute('device.service.openSettings', {
      'target': target,
    });
  }

  static Future<void> _editBlockedPackages(
    BuildContext context,
    FloatingAssistantSettings settings,
  ) async {
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => TextEditingControllerHost(
        initialTexts: [settings.blockedPackages.join('\n')],
        builder: (ctx, controllers) {
          final controller = controllers.single;
          return AlertDialog(
            title: const Text('屏蔽应用包名'),
            content: SizedBox(
              width: double.maxFinite,
              child: TextField(
                controller: controller,
                maxLines: 8,
                minLines: 4,
                decoration: const InputDecoration(
                  hintText: '每行一个包名，如\ncom.example.app',
                  border: OutlineInputBorder(),
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, controller.text),
                child: const Text('保存'),
              ),
            ],
          );
        },
      ),
    );
    if (result == null) return;
    final packages = result
        .split('\n')
        .map((line) => line.trim())
        .where((line) => line.isNotEmpty)
        .toSet()
        .toList(growable: false);
    if (context.mounted) {
      _update(context, settings.copyWith(blockedPackages: packages));
    }
  }

  static void _openHistory(BuildContext context) {
    final chat = FloatingAssistantService.instance.chatController;
    if (chat == null) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => TranslationHistoryPage(controller: chat),
      ),
    );
  }
}

class _TranslationModelTile extends StatelessWidget {
  const _TranslationModelTile(this.settings);

  final FloatingAssistantSettings settings;

  @override
  Widget build(BuildContext context) {
    final models = context.watch<ModelConfigProvider>().models;
    final chatModels = models
        .where((m) => m.category == ModelConfig.categoryChat)
        .toList();
    final currentId = settings.translationModelId;
    final selected = currentId == null || currentId.isEmpty
        ? null
        : chatModels.firstWhere(
            (m) => m.id == currentId,
            orElse: () => chatModels.first,
          );
    final enabled = settings.enabled && settings.showMangaTranslationAction;
    return ListTile(
      leading: const Icon(Icons.translate),
      title: const Text('翻译模型'),
      subtitle: Text(
        selected == null
            ? '跟随当前聊天模型'
            : (selected.modelName.isEmpty ? selected.id : selected.modelName),
      ),
      enabled: enabled,
      trailing: DropdownButton<String?>(
        value: currentId,
        hint: const Text('跟随聊天模型'),
        items: [
          const DropdownMenuItem<String?>(value: null, child: Text('跟随聊天模型')),
          ...chatModels.map(
            (m) => DropdownMenuItem<String?>(
              value: m.id,
              child: Text(m.modelName.isEmpty ? m.id : m.modelName),
            ),
          ),
        ],
        onChanged: enabled
            ? (next) {
                FloatingAssistantSettingsPage._update(
                  context,
                  next == null
                      ? settings.copyWith(clearTranslationModel: true)
                      : settings.copyWith(translationModelId: next),
                );
              }
            : null,
      ),
    );
  }
}

class _UnsupportedPlatformCard extends StatelessWidget {
  const _UnsupportedPlatformCard();

  @override
  Widget build(BuildContext context) {
    return const Card(
      margin: EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: Icon(Icons.info_outline),
        title: Text('当前平台暂不支持'),
        subtitle: Text('系统级悬浮聊天、页面读取和屏幕翻译只在 Android 上实现。'),
      ),
    );
  }
}

class _OptionTile extends StatelessWidget {
  final String title;
  final String value;
  final Map<String, String> values;
  final bool enabled;
  final ValueChanged<String> onChanged;

  const _OptionTile({
    required this.title,
    required this.value,
    required this.values,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(title),
      trailing: DropdownButton<String>(
        value: values.containsKey(value) ? value : values.keys.first,
        onChanged: enabled
            ? (next) {
                if (next != null) onChanged(next);
              }
            : null,
        items: values.entries
            .map(
              (entry) =>
                  DropdownMenuItem(value: entry.key, child: Text(entry.value)),
            )
            .toList(growable: false),
      ),
    );
  }
}
