import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

/// 主题颜色自定义页面
///
/// 功能：
/// - 预设颜色快速选择（Material Design 颜色）
/// - 实时预览主题效果
/// - 点击颜色块即可切换主题
class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  /// 预设的颜色列表
  static const _presetColors = [
    Colors.blue,
    Colors.red,
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.orange,
    Colors.deepOrange,
    Colors.amber,
    Colors.brown,
    Colors.blueGrey,
    Colors.pink,
    Colors.cyan,
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final settings = provider.settings;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Theme'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 当前主题预览
            const Text(
              '当前主题预览',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            _buildThemePreview(context, settings.themeColor),
            const SizedBox(height: 24),

            // 预设颜色选择
            const Text(
              '选择主题颜色',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            // 颜色网格
            Wrap(
              spacing: 12,
              runSpacing: 12,
              children: _presetColors.map((color) {
                final isSelected =
                    color.toARGB32() == settings.themeColor.toARGB32();
                return _buildColorOption(
                  context,
                  color,
                  isSelected,
                  () => provider.setThemeColor(color),
                );
              }).toList(),
            ),
            const SizedBox(height: 24),

            // 自定义颜色选择器
            const Text(
              '自定义颜色',
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 12),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // 当前颜色显示
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: settings.themeColor,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.grey.withValues(alpha: 0.3),
                        ),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text('当前颜色'),
                          Text(
                            _colorToHex(settings.themeColor),
                            style: TextStyle(
                              color: Colors.grey[600],
                              fontFamily: 'monospace',
                            ),
                          ),
                        ],
                      ),
                    ),
                    // 颜色滑块（简化版，使用 Hue 选择）
                    SizedBox(
                      width: 120,
                      child: SliderTheme(
                        data: SliderThemeData(
                          trackHeight: 8,
                          thumbShape: const RoundSliderThumbShape(
                              enabledThumbRadius: 12),
                          activeTrackColor: settings.themeColor,
                        ),
                        child: Slider(
                          value: HSVColor.fromColor(settings.themeColor)
                              .hue,
                          min: 0,
                          max: 360,
                          divisions: 360,
                          onChanged: (hue) {
                            final newColor = HSLColor.fromAHSL(
                              1.0,
                              hue,
                              0.6,
                              0.5,
                            ).toColor();
                            provider.setThemeColor(newColor);
                          },
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// 构建主题预览卡片
  ///
  /// 展示当前主题颜色在不同 UI 元素上的效果。
  Widget _buildThemePreview(BuildContext context, Color themeColor) {
    return Card(
      elevation: 0,
      color: themeColor.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 模拟 AppBar
            Container(
              height: 40,
              decoration: BoxDecoration(
                color: themeColor,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Center(
                child: Text(
                  'AppBar',
                  style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 12),
            // 模拟按钮
            Row(
              children: [
                ElevatedButton(
                  onPressed: () {},
                  style: ElevatedButton.styleFrom(
                    backgroundColor: themeColor,
                    foregroundColor: Colors.white,
                  ),
                  child: const Text('按钮'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {},
                  style: OutlinedButton.styleFrom(
                    foregroundColor: themeColor,
                  ),
                  child: const Text('按钮'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // 模拟底部导航
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                Icon(Icons.history, color: themeColor, size: 24),
                Icon(Icons.chat_bubble, color: themeColor, size: 24),
                Icon(Icons.settings, color: themeColor, size: 24),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// 构建颜色选项
  Widget _buildColorOption(
    BuildContext context,
    Color color,
    bool isSelected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.black : Colors.transparent,
            width: isSelected ? 3 : 0,
          ),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: color.withValues(alpha: 0.4),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: isSelected
            ? const Icon(Icons.check, color: Colors.white, size: 24)
            : null,
      ),
    );
  }

  /// 将 Color 转换为 Hex 字符串
  String _colorToHex(Color color) {
    return '#${color.toARGB32().toRadixString(16).substring(2).toUpperCase()}';
  }
}

