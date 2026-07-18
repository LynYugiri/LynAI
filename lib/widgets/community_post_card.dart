import 'package:flutter/material.dart';

import '../models/community.dart';
import '../services/community_service.dart';
import 'latex_renderer.dart';

class CommunityPostCard extends StatelessWidget {
  const CommunityPostCard({
    super.key,
    required this.post,
    required this.service,
    required this.onOpen,
    required this.onAuthor,
    this.onLike,
    this.onFavorite,
    this.compact = false,
  });

  final CommunityPost post;
  final CommunityService service;
  final VoidCallback onOpen;
  final VoidCallback onAuthor;
  final VoidCallback? onLike;
  final VoidCallback? onFavorite;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.fromLTRB(12, 6, 12, 6),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onOpen,
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  CommunityAvatar(user: post.author, radius: 19),
                  const SizedBox(width: 10),
                  Expanded(
                    child: InkWell(
                      onTap: onAuthor,
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            post.author.displayName.isEmpty
                                ? '社区用户'
                                : post.author.displayName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            _postTime(post),
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (post.pinned)
                    const Tooltip(
                      message: '置顶',
                      child: Icon(Icons.push_pin, size: 18),
                    ),
                ],
              ),
              if (post.title.isNotEmpty) ...[
                const SizedBox(height: 12),
                Text(
                  post.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
              if (post.content.isNotEmpty) ...[
                const SizedBox(height: 8),
                compact
                    ? Text(
                        post.content,
                        maxLines: 5,
                        overflow: TextOverflow.ellipsis,
                      )
                    : SafeCommunityMarkdown(data: post.content),
              ],
              if (post.media.isNotEmpty) ...[
                const SizedBox(height: 12),
                CommunityMediaGrid(media: post.media, service: service),
              ],
              const SizedBox(height: 8),
              Row(
                children: [
                  _Action(
                    icon: post.liked ? Icons.favorite : Icons.favorite_border,
                    label: '${post.likeCount}',
                    selected: post.liked,
                    onPressed: onLike,
                  ),
                  _Action(
                    icon: Icons.mode_comment_outlined,
                    label: '${post.commentCount}',
                    onPressed: onOpen,
                  ),
                  const Spacer(),
                  _Action(
                    icon: post.favorited
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    label: post.favorited ? '已收藏' : '收藏',
                    selected: post.favorited,
                    onPressed: onFavorite,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class SafeCommunityMarkdown extends StatelessWidget {
  const SafeCommunityMarkdown({super.key, required this.data});

  final String data;

  @override
  Widget build(BuildContext context) {
    return MarkdownWithLatex(
      content: sanitizeCommunityMarkdown(data),
      selectable: true,
      renderMermaid: false,
    );
  }
}

String sanitizeCommunityMarkdown(String data) {
  var safe = data.replaceAllMapped(
    RegExp(r'!\[([^\]]*)\]\(([^)]+)\)'),
    (match) => match.group(1)!.trim().isEmpty
        ? '[远程图片已隐藏]'
        : '[图片: ${match.group(1)}]',
  );
  safe = safe.replaceAllMapped(RegExp(r'\[([^\]]+)\]\(([^)]+)\)'), (match) {
    final label = match.group(1)!;
    final rawTarget = match.group(2)!.trim().split(RegExp(r'\s+')).first;
    final uri = Uri.tryParse(rawTarget);
    final scheme = uri?.scheme.toLowerCase();
    return scheme == 'http' || scheme == 'https' ? match.group(0)! : label;
  });
  return safe.replaceAll(RegExp(r'<\/?[A-Za-z][^>]*>'), '');
}

class CommunityMediaGrid extends StatelessWidget {
  const CommunityMediaGrid({
    super.key,
    required this.media,
    required this.service,
  });

  final List<CommunityMedia> media;
  final CommunityService service;

  @override
  Widget build(BuildContext context) {
    final count = media.length;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: count == 1
            ? 1
            : count == 2
            ? 2
            : 3,
        mainAxisSpacing: 4,
        crossAxisSpacing: 4,
        childAspectRatio: count == 1 ? 16 / 9 : 1,
      ),
      itemCount: count,
      itemBuilder: (context, index) {
        final item = media[index];
        final declaredUrl = item.url?.trim() ?? '';
        final url =
            declaredUrl.isNotEmpty &&
                Uri.tryParse(declaredUrl)?.hasScheme == true
            ? declaredUrl
            : service.mediaUrl(item.id);
        return ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: Image.network(
            url,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(
              color: Theme.of(context).colorScheme.surfaceContainerHighest,
              child: const Center(child: Icon(Icons.broken_image_outlined)),
            ),
          ),
        );
      },
    );
  }
}

class CommunityAvatar extends StatelessWidget {
  const CommunityAvatar({super.key, required this.user, this.radius = 24});

  final CommunityUser user;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final avatar = user.avatarUrl;
    return CircleAvatar(
      radius: radius,
      foregroundImage: avatar != null && avatar.isNotEmpty
          ? NetworkImage(avatar)
          : null,
      child: Text(
        user.displayName.trim().isEmpty
            ? '?'
            : user.displayName.trim().characters.first.toUpperCase(),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.label,
    this.selected = false,
    this.onPressed,
  });

  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      onPressed: onPressed,
      icon: Icon(icon, size: 19),
      label: Text(label),
      style: TextButton.styleFrom(
        foregroundColor: selected
            ? Theme.of(context).colorScheme.primary
            : null,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

String formatCommunityTime(DateTime value) {
  final local = value.toLocal();
  String two(int value) => value.toString().padLeft(2, '0');
  return '${local.year}-${two(local.month)}-${two(local.day)} '
      '${two(local.hour)}:${two(local.minute)}';
}

String _postTime(CommunityPost post) {
  final updatedAt = post.updatedAt;
  if (updatedAt != null &&
      updatedAt.difference(post.createdAt).abs() >=
          const Duration(seconds: 1)) {
    return '${formatCommunityTime(post.createdAt)} · 已编辑';
  }
  return formatCommunityTime(post.createdAt);
}
