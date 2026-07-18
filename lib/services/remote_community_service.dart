import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/community.dart';
import 'backend_client.dart';
import 'community_service.dart';

class RemoteCommunityService implements CommunityService {
  RemoteCommunityService(this._client);

  final BackendClient _client;

  @override
  bool get isBackendConnected => _client.isConnected;

  @override
  String mediaUrl(String id) => '${_client.backendUrl}/community/media/$id';

  String _query(String path, int page, int pageSize) =>
      '$path?${Uri(queryParameters: {'page': '$page', 'page_size': '$pageSize'}).query}';

  Map<String, dynamic> _object(String body) {
    final decoded = jsonDecode(body);
    if (decoded is! Map) throw const CommunityException('社区返回了无效数据');
    return Map<String, dynamic>.from(decoded);
  }

  Map<String, dynamic> _entity(String body, String key) {
    final json = _object(body);
    final value = json[key];
    return value is Map ? Map<String, dynamic>.from(value) : json;
  }

  CommunityPageResult<T> _page<T>(
    String body,
    T Function(Map<String, dynamic>) parse,
    List<String> keys,
  ) {
    final json = _object(body);
    Object? raw;
    for (final key in keys) {
      raw ??= json[key];
    }
    raw ??= json['items'];
    final list = raw is List ? raw : const [];
    final items = list
        .whereType<Map>()
        .map((item) => parse(Map<String, dynamic>.from(item)))
        .toList(growable: false);
    final hasMore =
        json['hasMore'] == true ||
        json['has_more'] == true ||
        (json['nextPage'] ?? json['next_page']) != null;
    return CommunityPageResult(items: items, hasMore: hasMore);
  }

  void _expect(http.Response resp, Iterable<int> statusCodes) {
    if (statusCodes.contains(resp.statusCode)) return;
    throw CommunityException(
      BackendClient.extractErrorMessage(resp.body) ?? '社区请求失败',
    );
  }

  @override
  Future<CommunityPageResult<CommunityPost>> listPosts({
    int page = 1,
    int pageSize = 20,
  }) async {
    final resp = await _client.get(_query('/community/posts', page, pageSize));
    _expect(resp, const [200]);
    return _page(resp.body, CommunityPost.fromJson, const ['posts', 'entries']);
  }

  @override
  Future<CommunityPost> getPost(String id) async {
    final resp = await _client.get('/community/posts/$id');
    _expect(resp, const [200]);
    return CommunityPost.fromJson(_entity(resp.body, 'post'));
  }

  @override
  Future<CommunityPageResult<CommunityComment>> listComments(
    String postId, {
    int page = 1,
    int pageSize = 30,
  }) async {
    final resp = await _client.get(
      _query('/community/posts/$postId/comments', page, pageSize),
    );
    _expect(resp, const [200]);
    return _page(resp.body, CommunityComment.fromJson, const ['comments']);
  }

  @override
  Future<CommunityUser> getUser(String id) async {
    final resp = await _client.get('/community/users/$id');
    _expect(resp, const [200]);
    return CommunityUser.fromJson(_entity(resp.body, 'user'));
  }

  @override
  Future<CommunityPageResult<CommunityPost>> listUserPosts(
    String userId, {
    int page = 1,
    int pageSize = 20,
  }) async {
    final resp = await _client.get(
      _query('/community/users/$userId/posts', page, pageSize),
    );
    _expect(resp, const [200]);
    return _page(resp.body, CommunityPost.fromJson, const ['posts', 'entries']);
  }

  Map<String, Object> _postBody(
    String title,
    String content,
    List<String> mediaIds,
  ) => {'title': title, 'content': content, 'mediaIds': mediaIds};

  @override
  Future<CommunityPost> createPost({
    required String title,
    required String content,
    List<String> mediaIds = const [],
  }) async {
    final resp = await _client.post(
      '/community/posts',
      body: _postBody(title, content, mediaIds),
    );
    _expect(resp, const [200, 201]);
    return CommunityPost.fromJson(_entity(resp.body, 'post'));
  }

  @override
  Future<CommunityPost> updatePost(
    String id, {
    required String title,
    required String content,
    List<String> mediaIds = const [],
  }) async {
    final resp = await _client.patch(
      '/community/posts/$id',
      body: _postBody(title, content, mediaIds),
    );
    _expect(resp, const [200]);
    return CommunityPost.fromJson(_entity(resp.body, 'post'));
  }

  @override
  Future<void> deletePost(String id) async {
    final resp = await _client.delete('/community/posts/$id');
    _expect(resp, const [200, 204]);
  }

  @override
  Future<void> setPostLiked(String id, bool liked) async {
    final resp = liked
        ? await _client.put('/community/posts/$id/like')
        : await _client.delete('/community/posts/$id/like');
    _expect(resp, const [200, 204]);
  }

  @override
  Future<void> setPostFavorited(String id, bool favorited) async {
    final resp = favorited
        ? await _client.put('/community/posts/$id/favorite')
        : await _client.delete('/community/posts/$id/favorite');
    _expect(resp, const [200, 204]);
  }

  @override
  Future<CommunityPageResult<CommunityPost>> listFavorites({
    int page = 1,
    int pageSize = 20,
  }) async {
    final resp = await _client.get(
      _query('/community/me/favorites', page, pageSize),
    );
    _expect(resp, const [200]);
    return _page(resp.body, CommunityPost.fromJson, const [
      'posts',
      'favorites',
    ]);
  }

  @override
  Future<CommunityComment> createComment(String postId, String content) async {
    final resp = await _client.post(
      '/community/posts/$postId/comments',
      body: {'content': content},
    );
    _expect(resp, const [200, 201]);
    return CommunityComment.fromJson(_entity(resp.body, 'comment'));
  }

  @override
  Future<CommunityComment> updateComment(String id, String content) async {
    final resp = await _client.patch(
      '/community/comments/$id',
      body: {'content': content},
    );
    _expect(resp, const [200]);
    return CommunityComment.fromJson(_entity(resp.body, 'comment'));
  }

  @override
  Future<void> deleteComment(String id) async {
    final resp = await _client.delete('/community/comments/$id');
    _expect(resp, const [200, 204]);
  }

  @override
  Future<CommunityMedia> uploadMedia({
    required List<int> bytes,
    required String filename,
    String? contentType,
  }) async {
    final resp = await _client.multipartUpload(
      '/community/media',
      files: [
        BackendMultipartFile(
          field: 'file',
          bytes: bytes,
          filename: filename,
          contentType: contentType,
        ),
      ],
    );
    _expect(resp, const [200, 201]);
    return CommunityMedia.fromJson(_entity(resp.body, 'media'));
  }

  @override
  Future<CommunityUser> updateMyProfile({
    required String displayName,
    required String bio,
    String? avatarMediaId,
  }) async {
    final resp = await _client.patch(
      '/community/me/profile',
      body: {
        'displayName': displayName,
        'bio': bio,
        'avatarMediaId': ?avatarMediaId,
      },
    );
    _expect(resp, const [200]);
    return CommunityUser.fromJson(_entity(resp.body, 'user'));
  }

  @override
  Future<void> setPinnedPost(String id, bool pinned) async {
    final resp = pinned
        ? await _client.put('/community/me/pinned-post/$id')
        : await _client.delete('/community/me/pinned-post/$id');
    _expect(resp, const [200, 204]);
  }
}
