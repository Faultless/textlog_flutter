import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/feed.dart';
import 'package:textlog/state/pending_write.dart';
import 'package:textlog/state/providers.dart';

Map<String, dynamic> post(int id, {String body = 'body'}) => {
  'id': id,
  'body': body,
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': null,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'api_url': 'https://textlog.cc/api/v1/posts/$id',
  'author': {
    'handle': 'stagas',
    'url': 'https://textlog.cc/u/stagas',
    'api_url': 'https://textlog.cc/api/v1/users/stagas',
  },
};

void main() {
  group('PostCache', () {
    test('remembers and forgets', () {
      final cache = PostCache();
      final one = Post.fromJson(post(1));
      cache.remember([one]);
      expect(cache[1], one);
      cache.forget(1);
      expect(cache[1], isNull);
    });

    test('evicts the oldest entries past the limit', () {
      final cache = PostCache();
      cache.remember([for (var id = 1; id <= 600; id++) Post.fromJson(post(id))]);
      expect(cache[1], isNull, reason: 'oldest should be evicted');
      expect(cache[600], isNotNull, reason: 'newest should survive');
    });
  });

  test('a post already seen in a feed opens without a request', () async {
    final paths = <String>[];
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(
              jsonEncode({
                'data': [post(7)],
                'pagination': {'next_cursor': null},
              }),
              200,
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(feedProvider(const LatestFeed()).future);
    expect(paths, ['/api/v1/feeds/latest']);

    // Tapping that post must not hit the network again.
    final opened = await container.read(postProvider(7).future);
    expect(opened.id, 7);
    expect(paths, ['/api/v1/feeds/latest'], reason: 'no second request');
  });

  test('a settled reply evicts the cached post so the refresh is real', () async {
    final paths = <String>[];
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            paths.add(request.url.path);
            if (request.url.path == '/api/v1/posts/7') {
              return http.Response(jsonEncode({'data': post(7, body: 'fresh')}), 200);
            }
            return http.Response(
              jsonEncode({
                'data': [post(7, body: 'stale')],
                'pagination': {'next_cursor': null},
              }),
              200,
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(feedProvider(const LatestFeed()).future);
    expect((await container.read(postProvider(7).future)).body, 'stale');

    container.read(pendingWriteProvider.notifier).expect(const PendingReply(7));
    container.read(pendingWriteProvider.notifier).settle();

    expect((await container.read(postProvider(7).future)).body, 'fresh');
    expect(paths, contains('/api/v1/posts/7'));
  });
}
