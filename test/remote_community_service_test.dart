import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:lynai/services/backend_client.dart';
import 'package:lynai/services/remote_community_service.dart';

void main() {
  test('listPosts accepts snake_case pagination and model fields', () async {
    late Uri requested;
    final transport = _CommunityClient((request) async {
      requested = request.url;
      return _response(
        200,
        jsonEncode({
          'posts': [
            {
              'id': 12,
              'content': 'hello',
              'created_at': '2026-07-18T10:00:00Z',
              'like_count': 3,
              'author': {'id': 4, 'display_name': 'Lyn'},
            },
          ],
          'has_more': true,
        }),
      );
    });
    final client = BackendClient(client: transport)
      ..configure('https://example.test');
    addTearDown(client.close);

    final result = await RemoteCommunityService(
      client,
    ).listPosts(page: 2, pageSize: 15);

    expect(requested.path, '/community/posts');
    expect(requested.queryParameters, {'page': '2', 'page_size': '15'});
    expect(result.hasMore, isTrue);
    expect(result.items.single.id, '12');
    expect(result.items.single.author.displayName, 'Lyn');
    expect(result.items.single.likeCount, 3);
  });

  test('post mutation uses replay-safe PATCH after refresh', () async {
    var patches = 0;
    final bodies = <Map<String, dynamic>>[];
    final transport = _CommunityClient((request) async {
      if (request.url.path == '/auth/refresh') {
        return _response(
          200,
          jsonEncode({
            'token': {
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
            },
          }),
        );
      }
      patches++;
      bodies.add(
        Map<String, dynamic>.from(
          jsonDecode(await request.finalize().bytesToString()) as Map,
        ),
      );
      if (request.headers['Authorization'] != 'Bearer new-access') {
        return _response(401, 'expired');
      }
      return _response(
        200,
        jsonEncode({
          'post': {
            'id': 'p1',
            'title': 'updated',
            'content': 'body',
            'createdAt': '2026-07-18T10:00:00Z',
            'author': {'id': 'u1', 'displayName': 'User'},
          },
        }),
      );
    });
    final client = BackendClient(client: transport)
      ..configure('https://example.test')
      ..setTokens('old-access', 'old-refresh');
    addTearDown(client.close);

    final post = await RemoteCommunityService(client).updatePost(
      'p1',
      title: 'updated',
      content: 'body',
      mediaIds: const ['m1'],
    );

    expect(patches, 2);
    expect(
      bodies,
      everyElement({
        'title': 'updated',
        'content': 'body',
        'mediaIds': ['m1'],
      }),
    );
    expect(post.id, 'p1');
  });

  test('multipart media upload is replayable after refresh', () async {
    var uploads = 0;
    final transport = _CommunityClient((request) async {
      if (request.url.path == '/auth/refresh') {
        return _response(
          200,
          jsonEncode({
            'token': {
              'accessToken': 'new-access',
              'refreshToken': 'new-refresh',
            },
          }),
        );
      }
      uploads++;
      final body = await request.finalize().bytesToString();
      expect(body, contains('name="file"'));
      expect(body, contains('picture.png'));
      return request.headers['Authorization'] == 'Bearer new-access'
          ? _response(
              201,
              jsonEncode({
                'media': {'id': 'm1'},
              }),
            )
          : _response(401, 'expired');
    });
    final client = BackendClient(client: transport)
      ..configure('https://example.test')
      ..setTokens('old-access', 'old-refresh');
    addTearDown(client.close);

    final media = await RemoteCommunityService(client).uploadMedia(
      bytes: const [1, 2, 3],
      filename: 'picture.png',
      contentType: 'image/png',
    );

    expect(uploads, 2);
    expect(media.id, 'm1');
  });
}

http.StreamedResponse _response(int statusCode, String body) {
  final bytes = utf8.encode(body);
  return http.StreamedResponse(
    Stream.value(bytes),
    statusCode,
    contentLength: bytes.length,
  );
}

class _CommunityClient extends http.BaseClient {
  _CommunityClient(this.handler);

  final Future<http.StreamedResponse> Function(http.BaseRequest request)
  handler;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) =>
      handler(request);
}
