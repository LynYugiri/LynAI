import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../utils/plugin_path_utils.dart';

class PluginIcon extends StatelessWidget {
  final String pluginPath;
  final String? iconPath;
  final String? fallbackIconPath;
  final double size;
  final IconData fallbackIcon;
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

  String? _resolveIconPath(String? relativePath) {
    if (relativePath == null || relativePath.trim().isEmpty) return null;
    if (!isSupportedPluginImagePath(relativePath)) return null;
    final path = safePluginFilePath(pluginPath, relativePath);
    if (path == null || !File(path).existsSync()) return null;
    return path;
  }
}
