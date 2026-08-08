import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/feed.dart';
import 'package:textlog/state/pending_write.dart';
import 'package:textlog/state/providers.dart';

Map<String, dynamic> post(int id) => {
  'id': id,
  'body': 'post $id',
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

ProviderContainer containerWith(MockClient client) {
  final container = ProviderContainer(
    overrides: [httpClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('loads the first page for a source', () async {
    final container = containerWith(
      MockClient((request) async {
        expect(request.url.path, '/api/v1/tags/dart/posts');
        return http.Response(
          jsonEncode({
            'data': [post(2), post(1)],
            'pagination': {'next_cursor': null},
          }),
          200,
        );
      }),
    );

    final state = await container.read(feedProvider(const TagFeed('dart')).future);
    expect(state.posts.map((p) => p.id), [2, 1]);
    expect(state.hasMore, isFalse);
  });

  test('appends the next page and forwards the cursor', () async {
    final requested = <String?>[];
    final container = containerWith(
      MockClient((request) async {
        requested.add(request.url.queryParameters['cursor']);
        final first = requested.length == 1;
        return http.Response(
          jsonEncode({
            'data': first ? [post(2)] : [post(1)],
            'pagination': {'next_cursor': first ? 'Mg' : null},
          }),
          200,
        );
      }),
    );

    final source = const LatestFeed();
    await container.read(feedProvider(source).future);
    await container.read(feedProvider(source).notifier).loadMore();

    expect(requested, [null, 'Mg']);
    expect(container.read(feedProvider(source)).value!.posts.map((p) => p.id), [2, 1]);
  });

  test('a failed next page keeps the posts already loaded', () async {
    var calls = 0;
    final container = containerWith(
      MockClient((request) async {
        calls++;
        if (calls == 1) {
          return http.Response(
            jsonEncode({
              'data': [post(2)],
              'pagination': {'next_cursor': 'Mg'},
            }),
            200,
          );
        }
        return http.Response(
          jsonEncode({
            'error': {'code': 'rate_limited', 'message': 'Too many API requests'},
          }),
          429,
        );
      }),
    );

    final source = const LatestFeed();
    await container.read(feedProvider(source).future);
    await container.read(feedProvider(source).notifier).loadMore();

    final state = container.read(feedProvider(source)).value!;
    expect(state.posts.map((p) => p.id), [2]);
    expect((state.loadMoreError as ApiFailure).isRateLimited, isTrue);
  });

  test('surfaces the API error envelope', () async {
    final container = containerWith(
      MockClient(
        (_) async => http.Response(
          jsonEncode({
            'error': {'code': 'not_found', 'message': 'Post not found'},
          }),
          404,
        ),
      ),
    );

    await expectLater(
      container.read(postProvider(999).future),
      throwsA(isA<ApiFailure>().having((e) => e.isNotFound, 'isNotFound', isTrue)),
    );
  });

  test('a settled reply refreshes the thread and leaves the feeds alone', () async {
    final paths = <String>[];
    final container = containerWith(
      MockClient((request) async {
        paths.add(request.url.path);
        if (request.url.path == '/api/v1/posts/5') {
          return http.Response(jsonEncode({'data': post(5)}), 200);
        }
        return http.Response(
          jsonEncode({
            'data': [post(5)],
            'pagination': {'next_cursor': null},
          }),
          200,
        );
      }),
    );

    // Hold subscriptions so invalidation refetches instead of just disposing.
    container.listen(postProvider(5), (_, _) {}, fireImmediately: true);
    container.listen(feedProvider(const LatestFeed()), (_, _) {}, fireImmediately: true);
    await container.read(postProvider(5).future);
    await container.read(feedProvider(const LatestFeed()).future);
    final settled = paths.length;

    container.read(pendingWriteProvider.notifier).expect(const PendingReply(5));
    container.read(pendingWriteProvider.notifier).settle();
    // Await the rebuild rather than a bare microtask, or the assertion races it.
    await container.read(postProvider(5).future);
    await container.read(feedProvider(RepliesFeed(5)).future);

    final after = paths.sublist(settled);
    expect(container.read(pendingWriteProvider), isNull);
    expect(after, contains('/api/v1/posts/5'));
    expect(after, isNot(contains('/api/v1/feeds/latest')));
  });

  test('nothing refreshes when no write is pending', () async {
    final paths = <String>[];
    final container = containerWith(
      MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(jsonEncode({'data': post(1)}), 200);
      }),
    );
    container.listen(postProvider(1), (_, _) {}, fireImmediately: true);
    await container.read(postProvider(1).future);
    final settled = paths.length;

    container.read(pendingWriteProvider.notifier).settle();
    await Future<void>.delayed(Duration.zero);

    expect(paths.length, settled);
  });
}
