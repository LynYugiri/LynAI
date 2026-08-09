import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path_provider/path_provider.dart';
import 'package:screenshot/screenshot.dart';

import '../../models/conversation.dart';
import '../../models/message.dart';
import '../../utils/share_image_utils.dart';

/// 聊天长图导出器。
///
/// 承载选中消息的长图分页、捕获、分享与保存逻辑，把 UI 状态
/// （选中集合、进行中标志、toast）与导出流程解耦。页面通过
/// [pageBuilder] 注入渲染 widget，并通过回调接收结果反馈。
class ChatImageExporter {
  ChatImageExporter({
    required ScreenshotController controller,
    required MethodChannel nativeTools,
    double pixelRatio = 2.5,
    int pageMaxWeight = 3600,
    int chunkLength = 2800,
    required void Function(String message) showSnack,
  }) : _controller = controller,
       _nativeTools = nativeTools,
       _pixelRatio = pixelRatio,
       _pageMaxWeight = pageMaxWeight,
       _chunkLength = chunkLength,
       _showSnack = showSnack;

  final ScreenshotController _controller;
  final MethodChannel _nativeTools;
  final double _pixelRatio;
  final int _pageMaxWeight;
  final int _chunkLength;
  final void Function(String message) _showSnack;

  /// 把选中消息生成为长图并分享；[onSelectionCleared] 在成功后回调，
  /// 由页面负责退出分享选择模式。
  Future<void> shareMessages({
    required Conversation conv,
    required Set<String> selectedIds,
    required Widget Function(List<Message> page, int pageNumber, int pageCount)
    pageBuilder,
    VoidCallback? onSelectionCleared,
  }) async {
    final images = await _capturePages(conv, selectedIds, pageBuilder);
    if (images.isEmpty) {
      _showSnack('生成长图失败，请重试');
      return;
    }
    try {
      final message = await shareOrSavePngImages(
        images: images,
        filePrefix: 'lynai_share',
        nativeTools: _nativeTools,
        clipboardMessage: '长图已复制到剪贴板',
        galleryMessage: '长图已保存到图库',
      );
      if (message != null) _showSnack(message);
      onSelectionCleared?.call();
    } catch (e) {
      _showSnack('分享失败: $e');
    }
  }

  /// 把选中消息生成长图并保存：移动端写入图库，桌面端写入下载目录。
  Future<void> saveMessages({
    required Conversation conv,
    required Set<String> selectedIds,
    required Widget Function(List<Message> page, int pageNumber, int pageCount)
    pageBuilder,
    VoidCallback? onSelectionCleared,
  }) async {
    final images = await _capturePages(conv, selectedIds, pageBuilder);
    if (images.isEmpty) {
      _showSnack('生成长图失败，请重试');
      return;
    }
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      if (Platform.isAndroid || Platform.isIOS) {
        await saveImagesToGallery(
          images: images,
          filePrefix: 'lynai_share',
          nativeTools: _nativeTools,
        );
        _showSnack(pluralImageDoneText('长图已保存到图库', images.length));
        onSelectionCleared?.call();
        return;
      }
      Directory? dir;
      if (isDesktopPlatform) {
        dir = await getDownloadsDirectory();
      } else {
        dir = null;
      }
      dir ??= await getApplicationDocumentsDirectory();
      final files = <File>[];
      for (var i = 0; i < images.length; i++) {
        final file = File(
          '${dir.path}/${numberedImageFileName('lynai_share', timestamp, i, images.length)}',
        );
        await file.writeAsBytes(images[i], flush: true);
        files.add(file);
      }
      _showSnack(_savedPathText(files));
      onSelectionCleared?.call();
    } catch (e) {
      _showSnack('保存失败: $e');
    }
  }

  Future<List<Uint8List>> _capturePages(
    Conversation conv,
    Set<String> selectedIds,
    Widget Function(List<Message> page, int pageNumber, int pageCount)
    pageBuilder,
  ) async {
    final selected = conv.messages
        .where((m) => selectedIds.contains(m.id))
        .toList(growable: false);
    if (selected.isEmpty) return const [];
    final pages = _shareMessagePages(selected);
    return captureLongImagePages(
      pageCount: pages.length,
      controller: _controller,
      pixelRatio: _pixelRatio,
      pageBuilder: (i, pageCount) => pageBuilder(
        pages[i],
        pageCount == 1 ? 0 : i + 1,
        pageCount == 1 ? 0 : pageCount,
      ),
    );
  }

  /// 把消息按内容与附件长度拆分为多个导出页，避免单页过长。
  List<List<Message>> _shareMessagePages(List<Message> messages) {
    final pages = <List<Message>>[];
    var page = <Message>[];
    var weight = 0;
    for (final message in messages.expand(_splitShareMessage)) {
      final nextWeight = _shareMessageWeight(message);
      if (page.isNotEmpty && weight + nextWeight > _pageMaxWeight) {
        pages.add(page);
        page = <Message>[];
        weight = 0;
      }
      page.add(message);
      weight += nextWeight;
    }
    if (page.isNotEmpty) pages.add(page);
    return pages;
  }

  /// 超长消息按段落拆分，附件与思考内容只保留在第一段。
  Iterable<Message> _splitShareMessage(Message message) sync* {
    final content = message.content.trim();
    if (content.length <= _chunkLength) {
      yield message;
      return;
    }

    final chunks = splitTextForExport(content, maxLength: _chunkLength);
    for (var i = 0; i < chunks.length; i++) {
      yield Message(
        id: '${message.id}_share_$i',
        role: message.role,
        content: chunks[i],
        images: i == 0 ? message.images : const [],
        thinkingContent: i == 0 ? message.thinkingContent : null,
        timestamp: message.timestamp,
      );
    }
  }

  int _shareMessageWeight(Message message) {
    return message.content.length + message.images.length * 800 + 300;
  }

  String _savedPathText(List<File> files) {
    if (files.length == 1) return '长图已保存到 ${files.single.path}';
    return '长图已拆分为 ${files.length} 张，保存到 ${files.first.parent.path}';
  }
}
