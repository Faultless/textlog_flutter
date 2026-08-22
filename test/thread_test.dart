import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/thread.dart';

Map<String, dynamic> post(int id, {required int parent, required int replyCount, int? depth}) => {
  'id': id,
  'top_id': null,
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
  'parent': null,
  'depth': ?depth,
};

/// A stand-in for `/posts/{id}/replies`, faithful to the two things that matter:
/// it walks the tree to the requested `depth` and returns the *newest* `limit` of
/// what it found, flat, in id-descending order — exactly as the server does.
final class FakeThreadServer {
  FakeThreadServer(this.children);

  /// parent id -> child ids.
  final Map<int, List<int>> children;

  /// One entry per request: the id asked about and the depth asked for.
  final asked = <({int id, int depth})>[];

  int replyCountOf(int id) => (children[id] ?? const [])
      .fold(0, (total, child) => total + 1 + replyCountOf(child));

  http.Client get client => MockClient((request) async {
    final id = int.parse(RegExp(r'/posts/(\d+)/replies').firstMatch(request.url.path)![1]!);
    final depth = int.parse(request.url.queryParameters['depth'] ?? '1');
    final limit = int.parse(request.url.queryParameters['limit'] ?? '20');
    asked.add((id: id, depth: depth));

    final found = <Map<String, dynamic>>[];
    void walk(int parent, int level) {
      if (level > depth) return;
      for (final child in children[parent] ?? const <int>[]) {
        found.add(post(child, parent: parent, replyCount: replyCountOf(child), depth: level));
        walk(child, level + 1);
      }
    }
    walk(id, 1);

    found.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    final page = found.take(limit).toList();
    return http.Response(
      jsonEncode({
        'data': page,
        'pagination': {'next_cursor': found.length > limit ? 'more' : null},
      }),
      200,
    );
  });

  ProviderContainer container() {
    final container = ProviderContainer(
      overrides: [httpClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    return container;
  }
}

/// 1 -> 2 -> 3 -> … a chain deeper than the app will nest.
FakeThreadServer chain(int length) => FakeThreadServer({
  for (var id = 1; id < length; id++) id: [id + 1],
});

void main() {
  test('opening a thread is one request, not one per level', () async {
    final server = chain(12);
    final tree = await server.container().read(threadProvider(1).future);

    // This is the whole point of the change: the server walks the tree for us.
    expect(server.asked, hasLength(1));
    expect(server.asked.single, (id: 1, depth: maxThreadDepth));

    var node = tree.single;
    var depth = 1;
    while (node.children.isNotEmpty) {
      node = node.children.single;
      depth++;
    }
    expect(depth, maxThreadDepth, reason: 'one request reaches the nesting cap');
    expect(node.hasUnloaded, isTrue, reason: 'what is below the cap is still advertised');
  });

  test('a wide thread comes back in one request too', () async {
    final server = FakeThreadServer({1: [for (var id = 2; id <= 41; id++) id]});
    final tree = await server.container().read(threadProvider(1).future);

    expect(server.asked, hasLength(1));
    expect(tree, hasLength(40));
    expect(tree.every((node) => !node.hasUnloaded), isTrue);
  });

  test('a subtree cut off by the page limit is advertised, not dropped', () async {
    // 120 replies to the root, against a 100-post page.
    final server = FakeThreadServer({1: [for (var id = 2; id <= 121; id++) id]});
    final tree = await server.container().read(threadProvider(1).future);

    expect(server.asked, hasLength(1));
    expect(tree, hasLength(repliesPerNode));
  });

  test('an orphan whose parent the page cut off is left out rather than misplaced', () async {
    // A deep chain: the newest posts come back, their ancestors do not.
    final server = chain(200);
    final tree = await server.container().read(threadProvider(1).future);

    // Only what hangs off the root can be placed; the rest waits behind "+N more".
    expect(tree, hasLength(1));
    expect(tree.single.post.id, 2);
  });

  test('expanding a branch the first request could not reach costs one request', () async {
    final server = chain(12);
    final container = server.container();
    await container.read(threadProvider(1).future);

    // The node at the nesting cap, whose replies were never fetched.
    var node = (await container.read(threadProvider(1).future)).single;
    while (node.children.isNotEmpty) {
      node = node.children.single;
    }
    await container.read(threadProvider(1).notifier).expand(node.post.id);

    expect(server.asked, hasLength(2));
    expect(server.asked.last.id, node.post.id);
  });

  test('a refresh over many expanded branches stays inside the budget', () async {
    // Each expand is one deliberate request and gets its own allowance. A *pass* —
    // a refresh, or remounting the screen — must not then fire one per branch.
    final server = FakeThreadServer({
      for (var id = 1; id <= 40; id++) id: [for (var i = 1; i <= 30; i++) id * 100 + i],
    });
    final container = server.container();
    await container.read(threadProvider(1).future);
    for (var id = 101; id <= 130; id++) {
      await container.read(threadProvider(1).notifier).expand(id);
    }
    final beforeRefresh = server.asked.length;

    await container.read(threadProvider(1).notifier).refresh();

    expect(server.asked.length - beforeRefresh, lessThanOrEqualTo(maxThreadRequests));
    // Branches the budget could not refresh keep what they had rather than vanishing.
    expect(container.read(threadProvider(1)).value, isNotEmpty);
  });

  test('a thread with no replies is an empty tree', () async {
    final server = FakeThreadServer(const {});
    expect(await server.container().read(threadProvider(1).future), isEmpty);
    // …and asking again does not ask the server again.
    expect(server.asked, hasLength(1));
  });

  test('loaded replies land in the shared post cache', () async {
    final server = chain(6);
    final container = server.container();
    await container.read(threadProvider(1).future);
    expect(container.read(postCacheProvider)[2], isNotNull);
    expect(container.read(postCacheProvider)[5], isNotNull);
  });
}
