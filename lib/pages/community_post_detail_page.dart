import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/community.dart';
import '../providers/account_provider.dart';
import '../services/community_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/community_post_card.dart';
import '../widgets/login_dialog.dart';
import 'community_post_editor_page.dart';
import 'community_profile_page.dart';

class CommunityPostDetailPage extends StatefulWidget {
  const CommunityPostDetailPage({
    super.key,
    required this.service,
    required this.post,
  });

  final CommunityService service;
  final CommunityPost post;

  @override
  State<CommunityPostDetailPage> createState() =>
      _CommunityPostDetailPageState();
}

class _CommunityPostDetailPageState extends State<CommunityPostDetailPage> {
  late CommunityPost _post;
  List<CommunityComment> _comments = const [];
  bool _loading = true;
  bool _submitting = false;
  String? _error;
  final _commentController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _post = widget.post;
    _load();
  }

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final results = await Future.wait([
        widget.service.getPost(_post.id),
        widget.service.listComments(_post.id),
      ]);
      if (!mounted) return;
      setState(() {
        _post = results[0] as CommunityPost;
        _comments = (results[1] as CommunityPageResult<CommunityComment>).items;
        _loading = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final mine = account.user?.id == _post.author.id;
    final canDeletePost = mine || account.user?.isAdmin == true;
    return Scaffold(
      appBar: AppBar(
        title: const Text('动态详情'),
        actions: [
          if (canDeletePost)
            PopupMenuButton<String>(
              onSelected: _handleMenu,
              itemBuilder: (_) => [
                if (mine) const PopupMenuItem(value: 'edit', child: Text('编辑')),
                if (mine)
                  PopupMenuItem(
                    value: 'pin',
                    child: Text(_post.pinned ? '取消置顶' : '置顶到主页'),
                  ),
                const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: RefreshIndicator(
              onRefresh: _load,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                children: [
                  CommunityPostCard(
                    post: _post,
                    service: widget.service,
                    onOpen: () {},
                    onAuthor: _openAuthor,
                    onLike: () => _toggleLike(account),
                    onFavorite: () => _toggleFavorite(account),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
                    child: Text(
                      '评论 ${_post.commentCount}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (_loading)
                    const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(child: CircularProgressIndicator()),
                    )
                  else if (_error != null)
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        children: [
                          Text(_error!),
                          TextButton(onPressed: _load, child: const Text('重试')),
                        ],
                      ),
                    )
                  else if (_comments.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(28),
                      child: Center(child: Text('还没有评论')),
                    )
                  else
                    for (final comment in _comments)
                      _CommentTile(
                        comment: comment,
                        canEdit: account.user?.id == comment.author.id,
                        canDelete:
                            account.user?.id == comment.author.id ||
                            mine ||
                            account.user?.isAdmin == true,
                        onEdit: () => _editComment(comment),
                        onDelete: () => _deleteComment(comment),
                      ),
                ],
              ),
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _commentController,
                      enabled: !_submitting,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: account.isLoggedIn ? '写下评论' : '登录后参与评论',
                        border: const OutlineInputBorder(),
                        isDense: true,
                      ),
                      onTap: account.isLoggedIn ? null : _ensureLogin,
                    ),
                  ),
                  const SizedBox(width: 8),
                  IconButton.filled(
                    onPressed: _submitting ? null : _submitComment,
                    icon: const Icon(Icons.send),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<bool> _ensureLogin() async {
    if (context.read<AccountProvider>().isLoggedIn) return true;
    await showDialog<void>(
      context: context,
      builder: (_) => const LoginDialog(),
    );
    return mounted && context.read<AccountProvider>().isLoggedIn;
  }

  Future<void> _toggleLike(AccountProvider account) async {
    if (!await _ensureLogin()) return;
    final next = !_post.liked;
    setState(() {
      _post = _post.copyWith(
        liked: next,
        likeCount: (_post.likeCount + (next ? 1 : -1)).clamp(0, 1 << 31),
      );
    });
    try {
      await widget.service.setPostLiked(_post.id, next);
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _post = _post.copyWith(
          liked: !next,
          likeCount: (_post.likeCount + (next ? -1 : 1)).clamp(0, 1 << 31),
        );
      });
      showErrorSnackBar(context, '操作失败', details: error.toString());
    }
  }

  Future<void> _toggleFavorite(AccountProvider account) async {
    if (!await _ensureLogin()) return;
    final next = !_post.favorited;
    setState(() => _post = _post.copyWith(favorited: next));
    try {
      await widget.service.setPostFavorited(_post.id, next);
    } catch (error) {
      if (!mounted) return;
      setState(() => _post = _post.copyWith(favorited: !next));
      showErrorSnackBar(context, '操作失败', details: error.toString());
    }
  }

  Future<void> _submitComment() async {
    if (!await _ensureLogin()) return;
    final content = _commentController.text.trim();
    if (content.isEmpty) return;
    setState(() => _submitting = true);
    try {
      final comment = await widget.service.createComment(_post.id, content);
      if (!mounted) return;
      _commentController.clear();
      setState(() {
        _comments = [..._comments, comment];
        _post = _post.copyWith(commentCount: _post.commentCount + 1);
        _submitting = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _submitting = false);
      showErrorSnackBar(context, '评论失败', details: error.toString());
    }
  }

  Future<void> _editComment(CommunityComment comment) async {
    final controller = TextEditingController(text: comment.content);
    final content = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑评论'),
        content: TextField(controller: controller, minLines: 2, maxLines: 6),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (content == null || content.isEmpty) return;
    try {
      final updated = await widget.service.updateComment(comment.id, content);
      if (!mounted) return;
      setState(() {
        _comments = [
          for (final item in _comments)
            if (item.id == updated.id) updated else item,
        ];
      });
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, '修改失败', details: error.toString());
      }
    }
  }

  Future<void> _deleteComment(CommunityComment comment) async {
    try {
      await widget.service.deleteComment(comment.id);
      if (!mounted) return;
      setState(() {
        _comments = _comments.where((item) => item.id != comment.id).toList();
        _post = _post.copyWith(
          commentCount: (_post.commentCount - 1).clamp(0, 1 << 31),
        );
      });
    } catch (error) {
      if (mounted) {
        showErrorSnackBar(context, '删除失败', details: error.toString());
      }
    }
  }

  Future<void> _handleMenu(String action) async {
    if (action == 'edit') {
      final updated = await Navigator.push<CommunityPost>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CommunityPostEditorPage(service: widget.service, post: _post),
        ),
      );
      if (updated != null && mounted) setState(() => _post = updated);
      return;
    }
    if (action == 'pin') {
      try {
        await widget.service.setPinnedPost(_post.id, !_post.pinned);
        if (mounted) {
          setState(() => _post = _post.copyWith(pinned: !_post.pinned));
        }
      } catch (error) {
        if (mounted) {
          showErrorSnackBar(context, '置顶失败', details: error.toString());
        }
      }
      return;
    }
    if (action == 'delete') {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text('删除动态？'),
          content: const Text('动态将从社区中隐藏。'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, true),
              child: const Text('删除'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
      await widget.service.deletePost(_post.id);
      if (mounted) Navigator.pop(context, null);
    }
  }

  void _openAuthor() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityProfilePage(
          service: widget.service,
          userId: _post.author.id,
        ),
      ),
    );
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({
    required this.comment,
    required this.canEdit,
    required this.canDelete,
    required this.onEdit,
    required this.onDelete,
  });

  final CommunityComment comment;
  final bool canEdit;
  final bool canDelete;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: CommunityAvatar(user: comment.author, radius: 18),
      title: Text(comment.author.displayName),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SizedBox(height: 4),
          SafeCommunityMarkdown(data: comment.content),
          const SizedBox(height: 4),
          Text(formatCommunityTime(comment.createdAt)),
        ],
      ),
      trailing: canEdit || canDelete
          ? PopupMenuButton<String>(
              onSelected: (value) => value == 'edit' ? onEdit() : onDelete(),
              itemBuilder: (_) => [
                if (canEdit)
                  const PopupMenuItem(value: 'edit', child: Text('编辑')),
                if (canDelete)
                  const PopupMenuItem(value: 'delete', child: Text('删除')),
              ],
            )
          : null,
    );
  }
}
