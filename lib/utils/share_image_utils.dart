import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';
import 'package:share_plus/share_plus.dart';
import 'package:super_clipboard/super_clipboard.dart';

bool get isDesktopPlatform {
  return Platform.isLinux || Platform.isMacOS || Platform.isWindows;
}

/// 生成带序号后缀的导出图片文件名（单张无后缀）。
String numberedImageFileName(
  String prefix,
  int timestamp,
  int index,
  int total,
) {
  final suffix = total == 1 ? '' : '_part_${index + 1}_of_$total';
  return '${prefix}_$timestamp$suffix.png';
}

/// 生成“已完成共 N 张”的提示文案。
String pluralImageDoneText(String base, int count) {
  return count == 1 ? base : '$base，共 $count 张';
}

List<String> splitTextForExport(
  String text, {
  required int maxLength,
  bool trimInput = true,
  bool preferParagraphBreak = true,
}) {
  final source = trimInput ? text.trim() : text;
  if (source.length <= maxLength) return source.isEmpty ? [''] : [source];
  final chunks = <String>[];
  var start = 0;
  while (start < source.length) {
    var end = (start + maxLength).clamp(0, source.length);
    if (end < source.length) {
      final candidates = <int>[
        if (preferParagraphBreak) source.lastIndexOf('\n\n', end),
        source.lastIndexOf('\n', end),
        source.lastIndexOf(' ', end),
      ];
      final splitAt = candidates
          .where((i) => i > start + (maxLength ~/ 2))
          .fold<int>(-1, (best, i) => i > best ? i : best);
      if (splitAt != -1) end = splitAt;
    }
    final chunk = source.substring(start, end).trim();
    if (chunk.isNotEmpty) chunks.add(chunk);
    start = end;
  }
  return chunks.isEmpty ? [''] : chunks;
}

Future<String?> shareOrSavePngImages({
  required List<Uint8List> images,
  required String filePrefix,
  required MethodChannel nativeTools,
  required String clipboardMessage,
  required String galleryMessage,
}) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  if (isDesktopPlatform) {
    final clipboard = SystemClipboard.instance;
    if (clipboard == null) throw Exception('当前平台不支持写入剪贴板');
    final items = <DataWriterItem>[];
    for (var i = 0; i < images.length; i++) {
      final item = DataWriterItem(
        suggestedName: numberedImageFileName(
          filePrefix,
          timestamp,
          i,
          images.length,
        ),
      );
      item.add(Formats.png(images[i]));
      items.add(item);
    }
    await clipboard.write(items);
    return pluralImageDoneText(clipboardMessage, images.length);
  }

  if (Platform.isAndroid || Platform.isIOS) {
    await saveImagesToGallery(
      images: images,
      filePrefix: filePrefix,
      nativeTools: nativeTools,
    );
    return pluralImageDoneText(galleryMessage, images.length);
  }

  final dir = await getTemporaryDirectory();
  final files = <XFile>[];
  for (var i = 0; i < images.length; i++) {
    final file = File(
      '${dir.path}/${numberedImageFileName(filePrefix, timestamp, i, images.length)}',
    );
    await file.writeAsBytes(images[i], flush: true);
    files.add(XFile(file.path));
  }
  await SharePlus.instance.share(ShareParams(files: files));
  return null;
}

/// 把 PNG 图片逐张写入系统图库（仅 Android/iOS）。
Future<void> saveImagesToGallery({
  required List<Uint8List> images,
  required String filePrefix,
  required MethodChannel nativeTools,
}) async {
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  for (var i = 0; i < images.length; i++) {
    final result = await nativeTools
        .invokeMapMethod<String, dynamic>('saveImageToGallery', {
          'bytes': images[i],
          'fileName': numberedImageFileName(
            filePrefix,
            timestamp,
            i,
            images.length,
          ),
        });
    if (result?['ok'] != true) {
      throw Exception(result?['error'] ?? '保存到图库失败');
    }
  }
}

/// 逐页渲染分享长图并捕获为 PNG 列表。
///
/// 每页经 [pageBuilder] 生成（接收页码与总页数），先尝试长图捕获，
/// 失败时回退到普通捕获；720 像素宽度与 2.5 倍像素比与既有导出一致。
Future<List<Uint8List>> captureLongImagePages({
  required int pageCount,
  required Widget Function(int pageIndex, int pageCount) pageBuilder,
  required ScreenshotController controller,
  BuildContext? context,
  double pixelRatio = 2.5,
}) async {
  final images = <Uint8List>[];
  Future<Uint8List> captureOne(Widget widget) async {
    try {
      return await controller.captureFromLongWidget(
        widget,
        pixelRatio: pixelRatio,
        context: context,
        constraints: const BoxConstraints(maxWidth: 720),
      );
    } catch (_) {
      return controller.captureFromWidget(
        widget,
        pixelRatio: pixelRatio,
        context: context,
      );
    }
  }

  for (var i = 0; i < pageCount; i++) {
    images.add(await captureOne(pageBuilder(i, pageCount)));
  }
  return images;
}
