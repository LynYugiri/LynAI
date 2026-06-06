import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/plugin_path_utils.dart';

/// 插件图标组件。
///
/// 支持 SVG 和位图（PNG/JPG/WebP）格式的插件图标渲染。加载逻辑：
/// 1. 优先使用 [iconPath] 指定的图标文件
/// 2. 若不存在则回退到 [fallbackIconPath]
/// 3. 仍不存在则使用 Material 图标 [fallbackIcon] 兜底
///
/// 所有路径均通过 [safePluginFilePath] 校验，防止路径穿越。
class PluginIcon extends StatelessWidget {
  /// 插件安装目录的根路径。
  final String pluginPath;

  /// 图标文件的相对路径。
  final String? iconPath;

  /// 备用图标文件的相对路径。
  final String? fallbackIconPath;

  /// 图标显示尺寸。
  final double size;

  /// 所有路径均无效时使用的 Material 图标。
  final IconData fallbackIcon;

  /// 应用于 SVG 图标的前景色。
  final Color? color;

  const PluginIcon({
    super.key,
    required this.pluginPath,
    required this.iconPath,
    this.fallbackIconPath,
    this.size = 24,
    this.fallbackIcon = Icons.extension,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final path =
        _resolveIconPath(iconPath) ?? _resolveIconPath(fallbackIconPath);
    if (path == null) return Icon(fallbackIcon, size: size, color: color);
    if (path.toLowerCase().endsWith('.svg')) {
      return SvgPicture.file(
        File(path),
        width: size,
        height: size,
        fit: BoxFit.contain,
        placeholderBuilder: (_) => Icon(fallbackIcon, size: size, color: color),
      );
    }
    return Image.file(
      File(path),
      width: size,
      height: size,
      fit: BoxFit.contain,
      errorBuilder: (_, _, _) => Icon(fallbackIcon, size: size, color: color),
    );
  }

  /// 尝试将相对路径解析为插件目录下的真实文件路径。
  ///
  /// 返回 null 表示路径无效、不安全或文件不存在。
  String? _resolveIconPath(String? relativePath) {
    if (relativePath == null || relativePath.trim().isEmpty) return null;
    if (!isSupportedPluginImagePath(relativePath)) return null;
    final path = safePluginFilePath(pluginPath, relativePath);
    if (path == null || !File(path).existsSync()) return null;
    return path;
  }
}
