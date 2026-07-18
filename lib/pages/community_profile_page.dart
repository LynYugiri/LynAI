import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/community.dart';
import '../providers/account_provider.dart';
import '../services/community_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/community_post_card.dart';
import 'community_post_detail_page.dart';

class CommunityProfilePage extends StatefulWidget {
  const CommunityProfilePage({
    super.key,
    required this.service,
    required this.userId,
  });

  final CommunityService service;
  final String userId;

  @override
  State<CommunityProfilePage> createState() => _CommunityProfilePageState();
}

class _CommunityProfilePageState extends State<CommunityProfilePage> {
  CommunityUser? _user;
  List<CommunityPost> _posts = const [];
  bool _loading = true;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool more = false}) async {
    if (more && (!_hasMore || _loadingMore)) return;
    setState(() => more ? _loadingMore = true : _loading = true);
    try {
      final page = more ? _page + 1 : 1;
      final results = await Future.wait([
        if (!more) widget.service.getUser(widget.userId),
        widget.service.listUserPosts(widget.userId, page: page),
      ]);
      if (!mounted) return;
      final posts = results.last as CommunityPageResult<CommunityPost>;
      setState(() {
        if (!more) _user = results.first as CommunityUser;
        _posts = more ? [..._posts, ...posts.items] : posts.items;
        _page = page;
        _hasMore = posts.hasMore;
        _loading = false;
        _loadingMore = false;
        _error = null;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _loadingMore = false;
        _error = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mine = context.watch<AccountProvider>().user?.id == widget.userId;
    return Scaffold(
      appBar: AppBar(
        title: const Text('个人主页'),
        actions: [
          if (mine && _user != null)
            IconButton(
              tooltip: '编辑资料',
              onPressed: _editProfile,
              icon: const Icon(Icons.edit_outlined),
            ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 160),
                  Center(child: Text(_error!)),
                  Center(
                    child: TextButton(
                      onPressed: _load,
                      child: const Text('重试'),
                    ),
                  ),
                ],
              )
            : ListView(
                children: [
                  if (_user != null) _ProfileHeader(user: _user!),
                  const Divider(),
                  if (_posts.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(40),
                      child: Center(child: Text('还没有发布动态')),
                    ),
                  for (final post in _posts)
                    CommunityPostCard(
                      post: post,
                      service: widget.service,
                      compact: true,
                      onOpen: () => _openPost(post),
                      onAuthor: () {},
                    ),
                  if (_hasMore)
                    Center(
                      child: TextButton(
                        onPressed: _loadingMore
                            ? null
                            : () => _load(more: true),
                        child: Text(_loadingMore ? '加载中…' : '加载更多'),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  Future<void> _openPost(CommunityPost post) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CommunityPostDetailPage(service: widget.service, post: post),
      ),
    );
    if (mounted) _load();
  }

  Future<void> _editProfile() async {
    final name = TextEditingController(text: _user!.displayName);
    final bio = TextEditingController(text: _user!.bio);
    final save = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('编辑资料'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: name,
              maxLength: 32,
              decoration: const InputDecoration(labelText: '昵称'),
            ),
            TextField(
              controller: bio,
              maxLength: 200,
              minLines: 2,
              maxLines: 5,
              decoration: const InputDecoration(labelText: '简介'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('取消'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('保存'),
          ),
        ],
      ),
    );
    if (save == true) {
      try {
        final updated = await widget.service.updateMyProfile(
          displayName: name.text.trim(),
          bio: bio.text.trim(),
        );
        if (mounted) setState(() => _user = updated);
      } catch (error) {
        if (mounted) {
          showErrorSnackBar(context, '保存失败', details: error.toString());
        }
      }
    }
    name.dispose();
    bio.dispose();
  }
}

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final CommunityUser user;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        children: [
          CommunityAvatar(user: user, radius: 42),
          const SizedBox(height: 12),
          Text(user.displayName, style: Theme.of(context).textTheme.titleLarge),
          if (user.bio.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(user.bio, textAlign: TextAlign.center),
          ],
          const SizedBox(height: 12),
          Text('${user.postCount} 动态'),
        ],
      ),
    );
  }
}
