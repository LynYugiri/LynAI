import '../models/community.dart';

abstract class CommunityService {
  bool get isBackendConnected;

  String mediaUrl(String id);

  Future<CommunityPageResult<CommunityPost>> listPosts({
    int page = 1,
    int pageSize = 20,
  });

  Future<CommunityPost> getPost(String id);

  Future<CommunityPageResult<CommunityComment>> listComments(
    String postId, {
    int page = 1,
    int pageSize = 30,
  });

  Future<CommunityUser> getUser(String id);

  Future<CommunityPageResult<CommunityPost>> listUserPosts(
    String userId, {
    int page = 1,
    int pageSize = 20,
  });

  Future<CommunityPost> createPost({
    required String title,
    required String content,
    List<String> mediaIds = const [],
  });

  Future<CommunityPost> updatePost(
    String id, {
    required String title,
    required String content,
    List<String> mediaIds = const [],
  });

  Future<void> deletePost(String id);
  Future<void> setPostLiked(String id, bool liked);
  Future<void> setPostFavorited(String id, bool favorited);

  Future<CommunityPageResult<CommunityPost>> listFavorites({
    int page = 1,
    int pageSize = 20,
  });

  Future<CommunityComment> createComment(String postId, String content);
  Future<CommunityComment> updateComment(String id, String content);
  Future<void> deleteComment(String id);

  Future<CommunityMedia> uploadMedia({
    required List<int> bytes,
    required String filename,
    String? contentType,
  });

  Future<CommunityUser> updateMyProfile({
    required String displayName,
    required String bio,
    String? avatarMediaId,
  });

  Future<void> setPinnedPost(String id, bool pinned);
}
