import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/feed.dart';
import 'package:textlog/state/providers.dart';

Map<String, dynamic> post(
  int id, {
  int? parentId,
  Map<String, dynamic>? parent,
  int? topId,
  String handle = 'a',
}) => {
  'id': id,
  'top_id': topId,
  'body': 'post $id',
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': parentId,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'api_url': 'https://textlog.cc/api/v1/posts/$id',
  'author': {
    'handle': handle,
    'url': 'https://textlog.cc/u/$handle',
    'api_url': 'https://textlog.cc/api/v1/users/$handle',
  },
  'parent': parent,
};

void main() {
  test('a feed of replies costs one request, not one per quoted parent', () async {
    final paths = <String>[];
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            paths.add(request.url.path);
            return http.Response(
              jsonEncode({
                'data': [
                  for (var id = 100; id < 150; id++)
                    post(id, parentId: id - 50, parent: post(id - 50, handle: 'b')),
                ],
                'pagination': {'next_cursor': null},
              }),
              200,
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    final feed = await container.read(feedProvider(const LatestFeed()).future);

    expect(feed.posts, hasLength(50));
    // This used to be 51: the feed, then one fetch per parent quote on screen.
    expect(paths, ['/api/v1/feeds/latest']);
    expect(feed.posts.first.parent!.author.handle, 'b');
  });

  test('inlined parents are cached, so opening a quote is free', () async {
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': [post(100, parentId: 50, parent: post(50, topId: 10))],
                'pagination': {'next_cursor': null},
              }),
              200,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(feedProvider(const LatestFeed()).future);

    final cached = container.read(postCacheProvider)[50];
    expect(cached, isNotNull);
    expect(cached!.topId, 10, reason: 'so the quote can link to the top of its thread');
  });

  test('a quoted copy never overwrites a fuller one', () async {
    final cache = PostCache();
    final full = post(50, parentId: 20, parent: post(20));
    // The feed gives us post 50 with its own parent inlined…
    cache.remember([Post.fromJson(full)]);
    // …and later a reply quotes post 50, with no parent of its own.
    cache.remember([Post.fromJson(post(100, parentId: 50, parent: post(50, parentId: 20)))]);

    expect(cache[50]!.parent, isNotNull, reason: 'the grandparent we knew is kept');
    expect(cache[50]!.parent!.id, 20);
  });
}
