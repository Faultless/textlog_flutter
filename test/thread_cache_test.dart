import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/thread.dart';

Map<String, dynamic> post(int id, {required int parent, int replyCount = 0}) => {
  'id': id,
  'body': 'post $id',
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': parent,
  'reply_count': replyCount,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'api_url': 'https://textlog.cc/api/v1/posts/$id',
  'author': {
    'handle': 'a',
    'url': 'https://textlog.cc/u/a',
    'api_url': 'https://textlog.cc/api/v1/users/a',
  },
};

/// 1 -> 2 -> 3 -> 4 ... a chain deep enough to need several requests.
({ProviderContainer container, List<int> requested, void Function(Duration) advance})
setUp$() {
  final requested = <int>[];
  var clock = DateTime(2026, 8, 8, 12);

  final container = ProviderContainer(
    overrides: [
      nowProvider.overrideWithValue(() => clock),
      httpClientProvider.overrideWithValue(
        MockClient((request) async {
          final id = int.parse(
            RegExp(r'/posts/(\d+)/replies').firstMatch(request.url.path)![1]!,
          );
          requested.add(id);
          return http.Response(
            jsonEncode({
              'data': [post(id + 1, parent: id, replyCount: 1)],
              'pagination': {'next_cursor': null},
            }),
            200,
          );
        }),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (
    container: container,
    requested: requested,
    advance: (d) => clock = clock.add(d),
  );
}

void main() {
  test('reopening a thread costs no requests at all', () async {
    final t = setUp$();
    await t.container.read(threadProvider(1).future);
    final first = t.requested.length;
    expect(first, greaterThan(0));

    // Drop the provider, as leaving the screen does, then come back.
    t.container.invalidate(threadProvider(1));
    await t.container.read(threadProvider(1).future);

    expect(t.requested.length, first, reason: 'the replies cache outlives the provider');
  });

  test('opening a branch you already expanded costs nothing', () async {
    final t = setUp$();
    await t.container.read(threadProvider(1).future);
    await t.container.read(threadProvider(1).notifier).expand(2);
    final first = t.requested.length;

    // Following the reply into its own page.
    await t.container.read(threadProvider(2).future);

    expect(t.requested.length, first, reason: 'its replies are already cached');
  });

  test('a fresh thread is not revalidated on reopen', () async {
    final t = setUp$();
    await t.container.read(threadProvider(1).future);
    final first = t.requested.length;

    t.advance(const Duration(minutes: 1)); // still inside the TTL
    t.container.invalidate(threadProvider(1));
    await t.container.read(threadProvider(1).future);
    await Future<void>.delayed(Duration.zero);

    expect(t.requested.length, first);
  });

  test('a stale thread serves cache first, then revalidates behind the reader', () async {
    final t = setUp$();
    await t.container.read(threadProvider(1).future);
    final first = t.requested.length;

    t.advance(repliesTtl + const Duration(minutes: 1));
    t.container.invalidate(threadProvider(1));

    // The reader gets a tree without waiting on the network.
    final shown = await t.container.read(threadProvider(1).future);
    expect(shown, isNotEmpty);

    // …and the refresh lands afterwards.
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(t.requested.length, greaterThan(first), reason: 'stale entries refetched');
  });

  test('an explicit refresh refetches even when nothing has aged out', () async {
    final t = setUp$();
    await t.container.read(threadProvider(1).future);
    final first = t.requested.length;

    // Someone who pulls to refresh has usually just been told there is a new reply.
    // "Nothing has expired yet" is never the answer they wanted.
    await t.container.read(threadProvider(1).notifier).refresh();
    expect(t.requested.length, greaterThan(first));
  });

  test('a reply_count that disagrees with the cache invalidates it', () async {
    final t = setUp$();
    // The root's own count comes from the post cache: it never appears in its own
    // replies, so without having seen it there is nothing to compare against.
    t.container.read(postCacheProvider).remember([
      Post.fromJson(post(1, parent: 0, replyCount: 1)),
    ]);
    await t.container.read(threadProvider(1).future);
    final first = t.requested.length;

    // The thread now claims two replies where it claimed one. A feed or a live post
    // carrying that count is enough to know our copy is stale, at no request cost.
    t.container.read(repliesCacheProvider).noticeCounts([
      Post.fromJson(post(1, parent: 0, replyCount: 2)),
    ]);

    t.container.invalidate(threadProvider(1));
    await t.container.read(threadProvider(1).future);

    expect(t.requested.sublist(first), contains(1));
  });

  test('a matching reply_count leaves the cache alone', () async {
    final t = setUp$();
    t.container.read(postCacheProvider).remember([
      Post.fromJson(post(1, parent: 0, replyCount: 1)),
    ]);
    await t.container.read(threadProvider(1).future);
    final first = t.requested.length;

    t.container.read(repliesCacheProvider).noticeCounts([
      Post.fromJson(post(1, parent: 0, replyCount: 1)),
    ]);

    t.container.invalidate(threadProvider(1));
    await t.container.read(threadProvider(1).future);

    expect(t.requested.length, first);
  });

  test('a count it has never seen is left alone rather than guessed at', () async {
    // reply_count is a whole descendant count, so it cannot be checked against the
    // number of direct children held. Treating a mismatch there as staleness threw
    // away good replies on nearly every feed fetch.
    final t = setUp$();
    await t.container.read(threadProvider(1).future);
    final first = t.requested.length;

    t.container.read(repliesCacheProvider).noticeCounts([
      Post.fromJson(post(1, parent: 0, replyCount: 9)),
    ]);

    t.container.invalidate(threadProvider(1));
    await t.container.read(threadProvider(1).future);

    expect(t.requested.length, first);
  });

  test('one pass never exceeds the request budget', () async {
    final requested = <int>[];
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            final id = int.parse(
              RegExp(r'/posts/(\d+)/replies').firstMatch(request.url.path)![1]!,
            );
            requested.add(id);
            // Every node branches 30 ways, each child claiming replies of its own.
            return http.Response(
              jsonEncode({
                'data': [
                  for (var i = 1; i <= 30; i++) post(id * 100 + i, parent: id, replyCount: 1),
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

    await container.read(threadProvider(1).future);
    expect(requested.length, lessThanOrEqualTo(maxThreadRequests));
  });
}
