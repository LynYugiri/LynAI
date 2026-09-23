import 'composer_reference.dart';
import 'message.dart';

/// 对话页输入框草稿：正文片段与暂存附件。
///
/// 附件沿用消息附件的形式（[MessageImage]），路径指向已复制进应用私有存储的文件，
/// 因此草稿恢复后仍能预览和发送；文件已被外部清理时由页面在恢复时丢弃。
class ComposerDraft {
  final List<ComposerSegment> segments;
  final List<MessageImage> images;

  const ComposerDraft({this.segments = const [], this.images = const []});

  bool get isEmpty => segments.isEmpty && images.isEmpty;

  Map<String, dynamic> toJson() => {
    'segments': composerSegmentsToJson(segments),
    'images': images.map((image) => image.toJson()).toList(),
  };

  /// 解析草稿；兼容早期只存片段列表的格式，损坏内容按空草稿处理。
  factory ComposerDraft.fromJson(Object? raw) {
    if (raw is List) {
      return ComposerDraft(segments: composerSegmentsFromJson(raw));
    }
    if (raw is! Map) return const ComposerDraft();
    final images = <MessageImage>[];
    for (final item in raw['images'] as List? ?? const []) {
      if (item is Map) {
        images.add(MessageImage.fromJson(Map<String, dynamic>.from(item)));
      }
    }
    return ComposerDraft(
      segments: composerSegmentsFromJson(raw['segments']),
      images: images,
    );
  }
}
