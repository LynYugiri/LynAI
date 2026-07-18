DateTime? _date(Object? value) {
  if (value is int) {
    return DateTime.fromMillisecondsSinceEpoch(
      value < 100000000000 ? value * 1000 : value,
    );
  }
  return DateTime.tryParse(value?.toString() ?? '');
}

String _string(Object? value) => value?.toString() ?? '';

int _integer(Object? value) {
  if (value is int) return value;
  return int.tryParse(value?.toString() ?? '') ?? 0;
}

bool _boolean(Object? value) {
  if (value is bool) return value;
  return value == 1 || value?.toString().toLowerCase() == 'true';
}

class CommunityUser {
  const CommunityUser({
    required this.id,
    required this.displayName,
    this.avatarUrl,
    this.bio = '',
    this.postCount = 0,
    this.followerCount = 0,
    this.pinnedPostId,
  });

  final String id;
  final String displayName;
  final String? avatarUrl;
  final String bio;
  final int postCount;
  final int followerCount;
  final String? pinnedPostId;

  factory CommunityUser.fromJson(Map<String, dynamic> json) {
    final avatar = _string(json['avatarUrl'] ?? json['avatar_url']);
    final pinned = _string(json['pinnedPostId'] ?? json['pinned_post_id']);
    return CommunityUser(
      id: _string(json['id'] ?? json['userId'] ?? json['user_id']),
      displayName: _string(
        json['displayName'] ?? json['display_name'] ?? json['name'],
      ),
      avatarUrl: avatar.isEmpty ? null : avatar,
      bio: _string(json['bio']),
      postCount: _integer(json['postCount'] ?? json['post_count']),
      followerCount: _integer(json['followerCount'] ?? json['follower_count']),
      pinnedPostId: pinned.isEmpty ? null : pinned,
    );
  }
}

class CommunityMedia {
  const CommunityMedia({
    required this.id,
    this.url,
    this.mimeType,
    this.width,
    this.height,
  });

  final String id;
  final String? url;
  final String? mimeType;
  final int? width;
  final int? height;

  factory CommunityMedia.fromJson(Map<String, dynamic> json) {
    final url = _string(json['url']);
    final mime = _string(json['mimeType'] ?? json['mime_type']);
    final width = _integer(json['width']);
    final height = _integer(json['height']);
    return CommunityMedia(
      id: _string(json['id'] ?? json['mediaId'] ?? json['media_id']),
      url: url.isEmpty ? null : url,
      mimeType: mime.isEmpty ? null : mime,
      width: width == 0 ? null : width,
      height: height == 0 ? null : height,
    );
  }
}

class CommunityPost {
  const CommunityPost({
    required this.id,
    required this.author,
    required this.content,
    required this.createdAt,
    this.title = '',
    this.updatedAt,
    this.media = const [],
    this.likeCount = 0,
    this.commentCount = 0,
    this.liked = false,
    this.favorited = false,
    this.pinned = false,
  });

  final String id;
  final CommunityUser author;
  final String title;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final List<CommunityMedia> media;
  final int likeCount;
  final int commentCount;
  final bool liked;
  final bool favorited;
  final bool pinned;

  factory CommunityPost.fromJson(Map<String, dynamic> json) {
    final authorJson = json['author'] ?? json['user'];
    final mediaJson = json['media'] ?? json['images'] ?? const [];
    return CommunityPost(
      id: _string(json['id']),
      author: CommunityUser.fromJson(
        authorJson is Map
            ? Map<String, dynamic>.from(authorJson)
            : <String, dynamic>{
                'id': json['userId'] ?? json['user_id'],
                'displayName':
                    json['displayName'] ?? json['display_name'] ?? '用户',
                'avatarUrl': json['avatarUrl'] ?? json['avatar_url'],
              },
      ),
      title: _string(json['title']),
      content: _string(json['content'] ?? json['body']),
      createdAt:
          _date(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt: _date(json['updatedAt'] ?? json['updated_at']),
      media: mediaJson is List
          ? mediaJson
                .whereType<Map>()
                .map(
                  (item) =>
                      CommunityMedia.fromJson(Map<String, dynamic>.from(item)),
                )
                .toList(growable: false)
          : const [],
      likeCount: _integer(json['likeCount'] ?? json['like_count']),
      commentCount: _integer(json['commentCount'] ?? json['comment_count']),
      liked: _boolean(json['liked'] ?? json['isLiked'] ?? json['is_liked']),
      favorited: _boolean(
        json['favorited'] ?? json['isFavorited'] ?? json['is_favorited'],
      ),
      pinned: _boolean(json['pinned'] ?? json['isPinned'] ?? json['is_pinned']),
    );
  }

  CommunityPost copyWith({
    int? likeCount,
    int? commentCount,
    bool? liked,
    bool? favorited,
    bool? pinned,
  }) {
    return CommunityPost(
      id: id,
      author: author,
      title: title,
      content: content,
      createdAt: createdAt,
      updatedAt: updatedAt,
      media: media,
      likeCount: likeCount ?? this.likeCount,
      commentCount: commentCount ?? this.commentCount,
      liked: liked ?? this.liked,
      favorited: favorited ?? this.favorited,
      pinned: pinned ?? this.pinned,
    );
  }
}

class CommunityComment {
  const CommunityComment({
    required this.id,
    required this.postId,
    required this.author,
    required this.content,
    required this.createdAt,
    this.updatedAt,
  });

  final String id;
  final String postId;
  final CommunityUser author;
  final String content;
  final DateTime createdAt;
  final DateTime? updatedAt;

  factory CommunityComment.fromJson(Map<String, dynamic> json) {
    final author = json['author'] ?? json['user'];
    return CommunityComment(
      id: _string(json['id']),
      postId: _string(json['postId'] ?? json['post_id']),
      author: CommunityUser.fromJson(
        author is Map
            ? Map<String, dynamic>.from(author)
            : <String, dynamic>{
                'id': json['userId'] ?? json['user_id'],
                'displayName':
                    json['displayName'] ?? json['display_name'] ?? '用户',
              },
      ),
      content: _string(json['content'] ?? json['body']),
      createdAt:
          _date(json['createdAt'] ?? json['created_at']) ?? DateTime.now(),
      updatedAt: _date(json['updatedAt'] ?? json['updated_at']),
    );
  }
}

class CommunityPageResult<T> {
  const CommunityPageResult({required this.items, required this.hasMore});

  final List<T> items;
  final bool hasMore;
}

class CommunityException implements Exception {
  const CommunityException(this.message);

  final String message;

  @override
  String toString() => message;
}
