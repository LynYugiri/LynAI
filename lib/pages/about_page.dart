import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

/// 关于页面
///
/// 显示应用的基本信息，包括名称、版本、描述等。
class AboutPage extends StatelessWidget {
  const AboutPage({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>().settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('About'),
        centerTitle: true,
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(32.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // 应用图标
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  color: settings.themeColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Icon(
                  Icons.smart_toy,
                  size: 60,
                  color: settings.themeColor,
                ),
              ),
              const SizedBox(height: 24),
              // 应用名称
              Text(
                'LynAI',
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 8),
              // 版本号
              Text(
                'Version 1.0.0',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[600],
                ),
              ),
              const SizedBox(height: 24),
              // 描述
              Text(
                '一款基于 Flutter 的 AI 对话应用',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.grey[700],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                '支持多种 AI 模型接口，提供流畅的对话体验。',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey[500],
                ),
              ),
              const SizedBox(height: 32),
              // 技术栈信息
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Theme.of(context)
                      .colorScheme
                      .surfaceContainerHighest
                      .withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  children: [
                    _buildInfoRow('框架', 'Flutter'),
                    const SizedBox(height: 8),
                    _buildInfoRow('语言', 'Dart'),
                    const SizedBox(height: 8),
                    _buildInfoRow('平台', _currentPlatform()),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: const TextStyle(fontWeight: FontWeight.w600)),
        Text(value, style: TextStyle(color: Colors.grey[600])),
      ],
    );
  }

  String _currentPlatform() {
    switch (defaultTargetPlatform) {
      case TargetPlatform.android: return 'Android';
      case TargetPlatform.iOS: return 'iOS';
      case TargetPlatform.macOS: return 'macOS';
      case TargetPlatform.linux: return 'Linux';
      case TargetPlatform.windows: return 'Windows';
      case TargetPlatform.fuchsia: return 'Fuchsia';
    }
  }
}

