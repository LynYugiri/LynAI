import 'package:flutter/material.dart';

import '../models/community.dart';
import '../services/community_service.dart';
import '../widgets/community_post_card.dart';
import 'community_post_detail_page.dart';
import 'community_profile_page.dart';

class CommunityFavoritesPage extends StatefulWidget {
  const CommunityFavoritesPage({super.key, required this.service});

  final CommunityService service;

  @override
  State<CommunityFavoritesPage> createState() => _CommunityFavoritesPageState();
}

class _CommunityFavoritesPageState extends State<CommunityFavoritesPage> {
  List<CommunityPost> _posts = const [];
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final result = await widget.service.listFavorites();
      if (!mounted) return;
      setState(() {
        _posts = result.items;
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
    return Scaffold(
      appBar: AppBar(title: const Text('我的收藏')),
      body: RefreshIndicator(
        onRefresh: _load,
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
            ? ListView(
                children: [
                  const SizedBox(height: 160),
                  Center(child: Text(_error!)),
                ],
              )
            : _posts.isEmpty
            ? ListView(
                children: const [
                  SizedBox(height: 160),
                  Center(child: Text('还没有收藏')),
                ],
              )
            : ListView.builder(
                itemCount: _posts.length,
                itemBuilder: (context, index) {
                  final post = _posts[index];
                  return CommunityPostCard(
                    post: post,
                    service: widget.service,
                    compact: true,
                    onOpen: () async {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => CommunityPostDetailPage(
                            service: widget.service,
                            post: post,
                          ),
                        ),
                      );
                      if (mounted) _load();
                    },
                    onAuthor: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CommunityProfilePage(
                          service: widget.service,
                          userId: post.author.id,
                        ),
                      ),
                    ),
                  );
                },
              ),
      ),
    );
  }
}
