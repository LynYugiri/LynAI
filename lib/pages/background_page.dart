import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

/// 背景图片设置页面
///
/// 功能：
/// - 从相册选择背景图片
/// - 预览背景图片效果
/// - 开启/关闭毛玻璃效果（BackdropFilter + ImageFilter.blur）
/// - 调整模糊程度（0-20）
class BackgroundPage extends StatefulWidget {
  const BackgroundPage({super.key});

  @override
  State<BackgroundPage> createState() => _BackgroundPageState();
}

class _BackgroundPageState extends State<BackgroundPage> {
  final _imagePicker = ImagePicker();

  /// 从相册选择图片
  Future<void> _pickImage() async {
    final pickedFile =
        await _imagePicker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      if (!mounted) return;
      context.read<SettingsProvider>().setBackgroundImage(pickedFile.path);
    }
  }

  /// 清除背景图片
  void _clearBackground() {
    context.read<SettingsProvider>().setBackgroundImage(null);
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final settings = provider.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Background'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 背景预览区域
            const Text(
              '背景预览',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            // 预览卡片 - 使用 BackdropFilter 实现毛玻璃效果
            Container(
              height: 200,
              width: double.infinity,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: Colors.grey.withValues(alpha: 0.3)),
              ),
              clipBehavior: Clip.antiAlias,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // 背景图片层
                  if (settings.backgroundImagePath != null)
                    Image.file(
                      File(settings.backgroundImagePath!),
                      fit: BoxFit.cover,
                      errorBuilder: (_, _, _) =>
                          _buildNoBackgroundPlaceholder(),
                    )
                  else
                    _buildNoBackgroundPlaceholder(),
                  // 毛玻璃效果覆盖层
                  if (settings.blurEnabled &&
                      settings.backgroundImagePath != null)
                    // BackdropFilter 会对背景进行模糊处理
                    BackdropFilter(
                      filter: ui.ImageFilter.blur(
                        sigmaX: settings.blurAmount,
                        sigmaY: settings.blurAmount,
                      ),
                      child: Container(
                        color: Colors.white.withValues(alpha: 0.1),
                      ),
                    ),
                  // 预览文字
                  Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        '预览效果',
                        style: TextStyle(color: Colors.white, fontSize: 14),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 24),

            // 选择背景图片
            const Text(
              '选择背景',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _pickImage,
                    icon: const Icon(Icons.photo_library),
                    label: const Text('从相册选择'),
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                if (settings.backgroundImagePath != null) ...[
                  const SizedBox(width: 12),
                  IconButton(
                    onPressed: _clearBackground,
                    icon: const Icon(Icons.delete_outline),
                    tooltip: '清除背景',
                    style: IconButton.styleFrom(
                      foregroundColor: Colors.red,
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 24),

            // 毛玻璃效果开关
            const Text(
              '毛玻璃效果',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Card(
              child: SwitchListTile(
                title: const Text('启用毛玻璃效果'),
                subtitle: const Text('为背景添加模糊效果'),
                value: settings.blurEnabled,
                onChanged: (value) {
                  provider.setBlurEnabled(value);
                },
              ),
            ),
            const SizedBox(height: 16),

            // 模糊程度滑块
            if (settings.blurEnabled) ...[
              const Text(
                '模糊程度',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    children: [
                      Row(
                        mainAxisAlignment:
                            MainAxisAlignment.spaceBetween,
                        children: [
                          const Text('清晰'),
                          Text(
                            settings.blurAmount.toStringAsFixed(1),
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          const Text('模糊'),
                        ],
                      ),
                      Slider(
                        value: settings.blurAmount,
                        min: 0.0,
                        max: 20.0,
                        divisions: 40,
                        label: settings.blurAmount.toStringAsFixed(1),
                        onChanged: (value) {
                          provider.setBlurAmount(value);
                        },
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 构建无背景时的占位符
  Widget _buildNoBackgroundPlaceholder() {
    return Container(
      color: Colors.grey[200],
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image, size: 48, color: Colors.grey[400]),
            const SizedBox(height: 8),
            Text(
              '未设置背景图片',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }
}

