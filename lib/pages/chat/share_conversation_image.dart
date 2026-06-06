part of '../chat_page.dart';

/// 对话分享长图组件。
///
/// 以卡片式布局渲染对话标题、消息气泡和附件，用于截图导出。
class _ShareConversationImage extends StatelessWidget {
  final String title;
  final List<Message> messages;
  final Color seedColor;
  final Brightness brightness;
  final int? pageNumber;
  final int? pageCount;

  const _ShareConversationImage({
    required this.title,
    required this.messages,
    required this.seedColor,
    required this.brightness,
    this.pageNumber,
    this.pageCount,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: seedColor,
      brightness: brightness,
    );
    final bgColor = Color.lerp(
      scheme.surface,
      scheme.primary,
      isDark ? 0.08 : 0.035,
    )!;
    final cardColor = Color.lerp(
      scheme.surface,
      scheme.surfaceContainerHighest,
      isDark ? 0.35 : 0.22,
    )!;
    final shadowColor = isDark ? Colors.black : Colors.black;
    final mutedColor = isDark
        ? const Color(0xFF94A3B8)
        : const Color(0xFF64748B);
    return Material(
      color: Colors.transparent,
      child: Container(
        width: 720,
        padding: const EdgeInsets.all(28),
        decoration: BoxDecoration(color: bgColor),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _ShareHeader(
              title: title,
              count: messages.length,
              scheme: scheme,
              mutedColor: mutedColor,
            ),
            const SizedBox(height: 22),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 18),
              decoration: BoxDecoration(
                color: cardColor,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(
                  color: scheme.outlineVariant.withValues(alpha: 0.55),
                ),
                boxShadow: [
                  BoxShadow(
                    color: shadowColor.withValues(alpha: isDark ? 0.22 : 0.08),
                    blurRadius: 20,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (var i = 0; i < messages.length; i++) ...[
                    _ShareMessageBubble(message: messages[i], scheme: scheme),
                    if (i != messages.length - 1) const SizedBox(height: 14),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 18),
            Text(
              pageNumber == null || pageCount == null
                  ? 'Shared from LynAI'
                  : 'Shared from LynAI · $pageNumber/$pageCount',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: mutedColor,
                fontSize: 18,
                letterSpacing: 0.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 分享图片头部区域。
///
/// 渲染应用图标、对话标题和已选消息条数统计。
class _ShareHeader extends StatelessWidget {
  final String title;
  final int count;
  final ColorScheme scheme;
  final Color mutedColor;

  const _ShareHeader({
    required this.title,
    required this.count,
    required this.scheme,
    required this.mutedColor,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: scheme.primary,
            borderRadius: BorderRadius.circular(18),
          ),
          child: Icon(Icons.auto_awesome, color: scheme.onPrimary, size: 30),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title.isEmpty ? 'LynAI 对话' : title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onSurface,
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                '$count 条精选消息 · ${DateTime.now().year}/${DateTime.now().month}/${DateTime.now().day}',
                style: TextStyle(color: mutedColor, fontSize: 16),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 分享图片中的消息气泡。
///
/// 区分用户和助手消息，使用不同颜色和圆形/方形角样式。
class _ShareMessageBubble extends StatelessWidget {
  final Message message;
  final ColorScheme scheme;

  const _ShareMessageBubble({required this.message, required this.scheme});

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    final bubbleColor = isUser
        ? scheme.primaryContainer
        : scheme.surfaceContainerHighest;
    final textColor = isUser ? scheme.onPrimaryContainer : scheme.onSurface;
    final labelColor = scheme.onSurfaceVariant;
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment: isUser
            ? CrossAxisAlignment.end
            : CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            isUser ? 'You' : 'LynAI',
            style: TextStyle(
              color: labelColor,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Container(
            constraints: const BoxConstraints(maxWidth: 560),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
            decoration: BoxDecoration(
              color: bubbleColor,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(22),
                topRight: const Radius.circular(22),
                bottomLeft: Radius.circular(isUser ? 22 : 6),
                bottomRight: Radius.circular(isUser ? 6 : 22),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (message.content.trim().isNotEmpty)
                  MarkdownWithLatex(
                    content: message.content.trim(),
                    selectable: false,
                    wrapCodeBlocks: true,
                    textStyle: TextStyle(
                      fontSize: 20,
                      height: 1.45,
                      color: textColor,
                    ),
                  ),
                if (message.images.isNotEmpty &&
                    message.content.trim().isNotEmpty)
                  const SizedBox(height: 12),
                if (message.images.isNotEmpty)
                  _ShareImageStrip(images: message.images),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ShareImageStrip extends StatelessWidget {
  final List<MessageImage> images;

  const _ShareImageStrip({required this.images});

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: images.map((image) {
        final file = File(image.path);
        if (!file.existsSync()) return const SizedBox.shrink();
        if (!image.isImage) {
          return Container(
            width: 220,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              children: [
                const Icon(Icons.insert_drive_file_outlined, size: 28),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    image.name,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 16),
                  ),
                ),
              ],
            ),
          );
        }
        return ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Image.file(file, width: 150, height: 150, fit: BoxFit.cover),
        );
      }).toList(),
    );
  }
}
