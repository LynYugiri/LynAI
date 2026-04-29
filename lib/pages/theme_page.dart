import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/settings_provider.dart';

class ThemePage extends StatelessWidget {
  const ThemePage({super.key});

  static const _presetColors = [
    Colors.blue,
    Colors.lightBlue,
    Colors.cyan,
    Colors.teal,
    Colors.green,
    Colors.lightGreen,
    Colors.lime,
    Colors.yellow,
    Colors.amber,
    Colors.orange,
    Colors.deepOrange,
    Colors.red,
    Colors.pink,
    Color(0xFFFFB7C5), // 樱花粉
    Color(0xFFFF6B81), // 珊瑚红
    Color(0xFFFF8C69), // 蜜桃
    Colors.purple,
    Colors.deepPurple,
    Colors.indigo,
    Color(0xFF6C5CE7), // 薰衣草紫
    Color(0xFFA29BFE), // 淡紫
    Color(0xFF636E72), // 石墨灰
    Colors.blueGrey,
    Colors.brown,
    Color(0xFFD4A574), // 卡其
    Color(0xFF2D3436), // 深炭
    Color(0xFF00B894), // 薄荷绿
    Color(0xFF55EFC4), // 浅薄荷
    Color(0xFF0984E3), // 宝蓝
    Color(0xFFE17055), // 砖红
    Color(0xFFFDCB6E), // 鹅黄
    Color(0xFFE84393), // 品红
    Color(0xFF6C5B7B), // 梅紫
    Color(0xFF355C7D), // 海军蓝
    Color(0xFFC06C84), // 豆沙
  ];

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<SettingsProvider>();
    final settings = provider.settings;

    return Scaffold(
      appBar: AppBar(title: const Text('Theme'), centerTitle: true),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('主题模式', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _buildThemeModeSelector(context, provider),
          const SizedBox(height: 24),
          const Text('当前主题预览', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _buildThemePreview(context, settings.themeColor),
          const SizedBox(height: 24),
          const Text('选择主题颜色', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10,
            children: _presetColors.map((color) {
              final isSelected = color.toARGB32() == settings.themeColor.toARGB32();
              return _buildColorOption(context, color, isSelected, () => provider.setThemeColor(color));
            }).toList(),
          ),
          const SizedBox(height: 24),
          const Text('调色板', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
          const SizedBox(height: 12),
          _ColorPalette(
            currentColor: settings.themeColor,
            onColorChanged: provider.setThemeColor,
          ),
        ]),
      ),
    );
  }

  Widget _buildThemeModeSelector(BuildContext context, SettingsProvider provider) {
    final mode = provider.themeMode;
    final modeLabels = {'light': '浅色模式', 'dark': '深色模式', 'system': '跟随系统'};
    return Card(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Row(
          children: [
            Expanded(child: ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(mode == 'light' ? Icons.light_mode : (mode == 'dark' ? Icons.dark_mode : Icons.settings_suggest),
                  color: Theme.of(context).colorScheme.primary),
              title: Text(modeLabels[mode] ?? '浅色模式'),
              subtitle: const Text('默认使用浅色模式'),
            )),
            DropdownButton<String>(
              value: mode,
              underline: const SizedBox(),
              items: [
                DropdownMenuItem(value: 'light', child: Text('浅色', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'dark', child: Text('深色', style: TextStyle(fontSize: 13))),
                DropdownMenuItem(value: 'system', child: Text('跟随系统', style: TextStyle(fontSize: 13))),
              ],
              onChanged: (v) { if (v != null) provider.setThemeMode(v); },
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThemePreview(BuildContext context, Color themeColor) {
    return Card(
      elevation: 0,
      color: themeColor.withValues(alpha: 0.05),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Container(
            height: 40, decoration: BoxDecoration(color: themeColor, borderRadius: BorderRadius.circular(8)),
            child: const Center(child: Text('AppBar', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
          ),
          const SizedBox(height: 12),
          Row(children: [
            ElevatedButton(onPressed: () {}, style: ElevatedButton.styleFrom(backgroundColor: themeColor, foregroundColor: Colors.white), child: const Text('按钮')),
            const SizedBox(width: 12),
            OutlinedButton(onPressed: () {}, style: OutlinedButton.styleFrom(foregroundColor: themeColor), child: const Text('按钮')),
          ]),
          const SizedBox(height: 12),
          Row(mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              Icon(Icons.history, color: themeColor, size: 24),
              Icon(Icons.chat_bubble, color: themeColor, size: 24),
              Icon(Icons.settings, color: themeColor, size: 24),
            ],
          ),
        ]),
      ),
    );
  }

  Widget _buildColorOption(BuildContext context, Color color, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44, height: 44,
        decoration: BoxDecoration(
          color: color,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: isSelected ? Colors.black : Colors.transparent, width: isSelected ? 3 : 0),
          boxShadow: isSelected ? [BoxShadow(color: color.withValues(alpha: 0.4), blurRadius: 8, offset: const Offset(0, 2))] : null,
        ),
        child: isSelected ? const Icon(Icons.check, color: Colors.white, size: 20) : null,
      ),
    );
  }
}

class _ColorPalette extends StatefulWidget {
  final Color currentColor;
  final ValueChanged<Color> onColorChanged;
  const _ColorPalette({required this.currentColor, required this.onColorChanged});

  @override
  State<_ColorPalette> createState() => _ColorPaletteState();
}

class _ColorPaletteState extends State<_ColorPalette> {
  double _hue = 0;
  double _saturation = 0.6;
  double _lightness = 0.5;

  @override
  void initState() {
    super.initState();
    final hsl = HSLColor.fromColor(widget.currentColor);
    _hue = hsl.hue;
    _saturation = hsl.saturation;
    _lightness = hsl.lightness;
  }

  @override
  void didUpdateWidget(_ColorPalette oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.currentColor != oldWidget.currentColor) {
      final hsl = HSLColor.fromColor(widget.currentColor);
      _hue = hsl.hue;
      _saturation = hsl.saturation;
      _lightness = hsl.lightness;
    }
  }

  void _updateColor() {
    widget.onColorChanged(HSLColor.fromAHSL(1, _hue, _saturation, _lightness.clamp(0.01, 1.0)).toColor());
  }

  @override
  Widget build(BuildContext context) {
    final previewColor = HSLColor.fromAHSL(1, _hue, _saturation, _lightness).toColor();
    final hex = '#${previewColor.toARGB32().toRadixString(16).substring(2).toUpperCase()}';

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 56, height: 56,
              decoration: BoxDecoration(color: previewColor, borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.withValues(alpha: 0.3))),
            ),
            const SizedBox(width: 16),
            Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('当前颜色', style: TextStyle(fontWeight: FontWeight.w500)),
              Text(hex, style: TextStyle(color: Colors.grey[600], fontFamily: 'monospace', fontSize: 16)),
              Text('H:${_hue.toInt()}° S:${(_saturation*100).toInt()}% L:${(_lightness*100).toInt()}%',
                  style: TextStyle(fontSize: 11, color: Colors.grey[500])),
            ]),
          ]),
          const SizedBox(height: 16),
          // Hue slider
          const Text('色相', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 4),
          _HueSlider(hue: _hue, onChanged: (v) { setState(() => _hue = v); _updateColor(); }),
          const SizedBox(height: 16),
          // Saturation-Lightness picker
          const Text('饱和度 / 亮度', style: TextStyle(fontSize: 13, color: Colors.grey)),
          const SizedBox(height: 4),
          _SaturationLightnessPicker(
            hue: _hue,
            saturation: _saturation,
            lightness: _lightness,
            onChanged: (s, l) {
              setState(() { _saturation = s; _lightness = l; });
              _updateColor();
            },
          ),
          const SizedBox(height: 16),
          // Quick brightness strip
          Row(children: [
            Expanded(child: _BrightnessStrip(hue: _hue, saturation: _saturation, selected: _lightness,
              onChanged: (v) { setState(() => _lightness = v); _updateColor(); })),
          ]),
        ]),
      ),
    );
  }
}

class _HueSlider extends StatelessWidget {
  final double hue;
  final ValueChanged<double> onChanged;
  const _HueSlider({required this.hue, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      return GestureDetector(
        onPanDown: (d) => onChanged((d.localPosition.dx / constraints.maxWidth * 360).clamp(0, 360)),
        onPanUpdate: (d) => onChanged((d.localPosition.dx / constraints.maxWidth * 360).clamp(0, 360)),
        child: Container(
          height: 28,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(colors: List.generate(
              7, (i) => HSLColor.fromAHSL(1, i * 60, 1, 0.5).toColor())),
          ),
          child: Stack(children: [
            Positioned(
              left: (hue / 360 * constraints.maxWidth) - 10,
              top: -2,
              child: Container(width: 20, height: 32, decoration: BoxDecoration(
                shape: BoxShape.circle, color: HSLColor.fromAHSL(1, hue, 1, 0.5).toColor(),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              )),
            ),
          ]),
        ),
      );
    });
  }
}

class _SaturationLightnessPicker extends StatelessWidget {
  final double hue, saturation, lightness;
  final Function(double s, double l) onChanged;
  const _SaturationLightnessPicker({required this.hue, required this.saturation, required this.lightness, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      final w = constraints.maxWidth;
      final h = 160.0;
      return GestureDetector(
        onPanDown: (d) { _update(d.localPosition, w, h); },
        onPanUpdate: (d) { _update(d.localPosition, w, h); },
        child: Container(
          width: w, height: h,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            color: HSLColor.fromAHSL(1, hue, 1, 0.5).toColor(),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(8),
            gradient: LinearGradient(
              colors: [Colors.white, Colors.white.withValues(alpha: 0)],
              begin: Alignment.centerLeft, end: Alignment.centerRight,
            ),
          ),
          child: Stack(children: [
            // Vertical black gradient (bottom=black→top=white overlay)
            Positioned.fill(child: Container(
              decoration: BoxDecoration(borderRadius: BorderRadius.circular(8),
                gradient: LinearGradient(
                  begin: Alignment.topCenter, end: Alignment.bottomCenter,
                  colors: [Colors.transparent, Colors.black],
                ),
              ),
            )),
            Positioned(
              left: saturation * w - 9,
              top: (1 - lightness) * h - 9,
              child: Container(width: 18, height: 18, decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: HSLColor.fromAHSL(1, hue, saturation, lightness).toColor(),
                border: Border.all(color: Colors.white, width: 3),
                boxShadow: [BoxShadow(color: Colors.black26, blurRadius: 4)],
              )),
            ),
          ]),
        ),
      );
    });
  }

  void _update(Offset pos, double w, double h) {
    final s = (pos.dx / w).clamp(0.0, 1.0);
    final l = (1 - pos.dy / h).clamp(0.0, 1.0);
    onChanged(s, l);
  }
}

class _BrightnessStrip extends StatelessWidget {
  final double hue, saturation, selected;
  final ValueChanged<double> onChanged;
  const _BrightnessStrip({required this.hue, required this.saturation, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (ctx, constraints) {
      return GestureDetector(
        onPanDown: (d) => onChanged((1 - d.localPosition.dx / constraints.maxWidth).clamp(0.01, 1.0)),
        onPanUpdate: (d) => onChanged((1 - d.localPosition.dx / constraints.maxWidth).clamp(0.01, 1.0)),
        child: Container(
          height: 24,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(6),
            gradient: LinearGradient(
              colors: [Colors.white, Colors.black],
              begin: Alignment.centerRight, end: Alignment.centerLeft,
            ),
          ),
          child: Stack(children: [
            Positioned(
              left: (1 - selected) * constraints.maxWidth - 8,
              top: -4,
              child: Container(width: 16, height: 32, decoration: BoxDecoration(
                shape: BoxShape.circle, color: Colors.white,
                border: Border.all(color: Colors.black26, width: 2),
              )),
            ),
          ]),
        ),
      );
    });
  }
}
