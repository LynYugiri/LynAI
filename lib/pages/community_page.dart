import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/community.dart';
import '../providers/account_provider.dart';
import '../services/backend_client.dart';
import '../services/community_service.dart';
import '../services/remote_community_service.dart';
import '../utils/snackbar_utils.dart';
import '../widgets/community_post_card.dart';
import '../widgets/login_dialog.dart';
import 'community_favorites_page.dart';
import 'community_post_detail_page.dart';
import 'community_post_editor_page.dart';
import 'community_profile_page.dart';

class CommunityPage extends StatefulWidget {
  const CommunityPage({
    super.key,
    required this.active,
    required this.onOpenSettings,
    this.communityService,
  });

  final bool active;
  final VoidCallback onOpenSettings;
  final CommunityService? communityService;

  @override
  State<CommunityPage> createState() => _CommunityPageState();
}

class _CommunityPageState extends State<CommunityPage> {
  CommunityService? _service;
  String? _stateScope;
  List<CommunityPost> _posts = const [];
  bool _started = false;
  bool _loading = false;
  bool _loadingMore = false;
  bool _hasMore = false;
  int _page = 1;
  int _loadGeneration = 0;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final account = context.watch<AccountProvider>();
    final backend = widget.communityService == null
        ? context.watch<BackendClient>()
        : null;
    _service = widget.communityService ?? RemoteCommunityService(backend!);
    final nextScope = widget.communityService == null
        ? '${backend!.backendScope}|${account.user?.id ?? 'guest'}'
        : 'injected|${account.user?.id ?? 'guest'}';
    if (_stateScope != null && _stateScope != nextScope) {
      _loadGeneration++;
      _posts = const [];
      _page = 1;
      _hasMore = false;
      _error = null;
      _started = false;
    }
    _stateScope = nextScope;
    _startIfActive();
  }

  @override
  void didUpdateWidget(covariant CommunityPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!oldWidget.active && widget.active) _startIfActive();
  }

  void _startIfActive() {
    if (!widget.active || _started) return;
    _started = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _load();
    });
  }

  Future<void> _load({bool more = false}) async {
    final service = _service!;
    final generation = _loadGeneration;
    if (!service.isBackendConnected) {
      setState(() {
        _loading = false;
        _error = null;
        _posts = const [];
      });
      return;
    }
    if (more && (!_hasMore || _loadingMore || _loading)) return;
    setState(() {
      more ? _loadingMore = true : _loading = true;
      _error = null;
    });
    try {
      final page = more ? _page + 1 : 1;
      final result = await service.listPosts(page: page);
      if (!mounted || generation != _loadGeneration) return;
      final byId = <String, CommunityPost>{
        if (more)
          for (final post in _posts) post.id: post,
        for (final post in result.items) post.id: post,
      };
      setState(() {
        _posts = byId.values.toList(growable: false);
        _page = page;
        _hasMore = result.hasMore;
        _loading = false;
        _loadingMore = false;
      });
    } catch (error) {
      if (!mounted || generation != _loadGeneration) return;
      setState(() {
        _error = error.toString();
        _loading = false;
        _loadingMore = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final account = context.watch<AccountProvider>();
    final service = _service;
    return Scaffold(
      appBar: AppBar(
        title: const Text('社区'),
        centerTitle: true,
        actions: [
          if (account.isLoggedIn && service != null)
            IconButton(
              tooltip: '我的收藏',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityFavoritesPage(service: service),
                ),
              ),
              icon: const Icon(Icons.bookmarks_outlined),
            ),
          if (account.isLoggedIn && service != null)
            IconButton(
              tooltip: '个人主页',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => CommunityProfilePage(
                    service: service,
                    userId: account.user!.id,
                  ),
                ),
              ),
              icon: const Icon(Icons.account_circle_outlined),
            ),
        ],
      ),
      body: service == null || !service.isBackendConnected
          ? _Disconnected(onOpenSettings: widget.onOpenSettings)
          : RefreshIndicator(onRefresh: _load, child: _body(service, account)),
      floatingActionButton: service?.isBackendConnected == true
          ? FloatingActionButton.extended(
              onPressed: () => _createPost(account),
              icon: const Icon(Icons.edit_outlined),
              label: const Text('发布'),
            )
          : null,
    );
  }

  Widget _body(CommunityService service, AccountProvider account) {
    if (_loading && _posts.isEmpty) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error != null && _posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 160),
          Center(child: Text(_error!)),
          Center(
            child: TextButton(onPressed: _load, child: const Text('重试')),
          ),
        ],
      );
    }
    if (_posts.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 160),
          Icon(Icons.forum_outlined, size: 64),
          SizedBox(height: 12),
          Center(child: Text('社区还没有动态')),
        ],
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.only(top: 6, bottom: 88),
      itemCount: _posts.length + (_hasMore ? 1 : 0),
      itemBuilder: (context, index) {
        if (index == _posts.length) {
          return Center(
            child: TextButton(
              onPressed: _loadingMore ? null : () => _load(more: true),
              child: Text(_loadingMore ? '加载中…' : '加载更多'),
            ),
          );
        }
        final post = _posts[index];
        return CommunityPostCard(
          post: post,
          service: service,
          compact: true,
          onOpen: () => _openPost(post),
          onAuthor: () => _openProfile(post.author.id),
          onLike: () => _toggleLike(post, account),
          onFavorite: () => _toggleFavorite(post, account),
        );
      },
    );
  }

  Future<bool> _ensureLogin(AccountProvider account) async {
    if (account.isLoggedIn) return true;
    await showDialog<void>(
      context: context,
      builder: (_) => const LoginDialog(),
    );
    return mounted && context.read<AccountProvider>().isLoggedIn;
  }

  Future<void> _createPost(AccountProvider account) async {
    if (!await _ensureLogin(account)) return;
    if (!mounted) return;
    final post = await Navigator.push<CommunityPost>(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityPostEditorPage(service: _service!),
      ),
    );
    if (post != null && mounted) setState(() => _posts = [post, ..._posts]);
  }

  Future<void> _openPost(CommunityPost post) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CommunityPostDetailPage(service: _service!, post: post),
      ),
    );
    if (mounted) _load();
  }

  void _openProfile(String userId) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            CommunityProfilePage(service: _service!, userId: userId),
      ),
    );
  }

  void _replace(CommunityPost post) {
    setState(() {
      _posts = [
        for (final item in _posts)
          if (item.id == post.id) post else item,
      ];
    });
  }

  Future<void> _toggleLike(CommunityPost post, AccountProvider account) async {
    if (!await _ensureLogin(account)) return;
    final next = !post.liked;
    _replace(
      post.copyWith(
        liked: next,
        likeCount: (post.likeCount + (next ? 1 : -1)).clamp(0, 1 << 31),
      ),
    );
    try {
      await _service!.setPostLiked(post.id, next);
    } catch (error) {
      if (!mounted) return;
      _replace(post);
      showErrorSnackBar(context, '操作失败', details: error.toString());
    }
  }

  Future<void> _toggleFavorite(
    CommunityPost post,
    AccountProvider account,
  ) async {
    if (!await _ensureLogin(account)) return;
    final next = !post.favorited;
    _replace(post.copyWith(favorited: next));
    try {
      await _service!.setPostFavorited(post.id, next);
    } catch (error) {
      if (!mounted) return;
      _replace(post);
      showErrorSnackBar(context, '操作失败', details: error.toString());
    }
  }
}

class _Disconnected extends StatelessWidget {
  const _Disconnected({required this.onOpenSettings});

  final VoidCallback onOpenSettings;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.cloud_off_outlined, size: 72),
            const SizedBox(height: 16),
            Text('尚未连接后端', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            const Text('配置 LynAI 后端后即可浏览公开社区。', textAlign: TextAlign.center),
            const SizedBox(height: 20),
            FilledButton.tonal(
              onPressed: onOpenSettings,
              child: const Text('打开设置'),
            ),
          ],
        ),
      ),
    );
  }
}
