import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/reply_tree.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/thread.dart';

Map<String, dynamic> post(
  int id, {
  required int parent,
  required int replyCount,
  int? depth,
  Map<String, dynamic>? parentPost,
}) => {
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
  // The server inlines the quoted parent on every post, which is what lets a
  // truncated page be repaired without another request.
  'parent': parentPost,
  'depth': ?depth,
};

/// `/posts/{id}/replies` as textlog implements it: walks to the requested depth, then
/// returns the **newest** `limit` of what it found, flat and id-descending.
final class FakeThread {
  FakeThread(this.children, {this.inlineParents = true});

  final Map<int, List<int>> children;

  /// The real server inlines a quoted parent on every post, which is what lets a
  /// truncated page be repaired for free. Turn it off to exercise what happens when
  /// it cannot be.
  final bool inlineParents;

  final asked = <String>[];

  /// The server's `reply_count` is a post's whole descendant count, not its
  /// direct-child count.
  int descendants(int id) =>
      (children[id] ?? const []).fold(0, (total, child) => total + 1 + descendants(child));

  int parentOf(int id) {
    for (final entry in children.entries) {
      if (entry.value.contains(id)) return entry.key;
    }
    return 0;
  }

  Map<String, dynamic> asJson(int id, {int? depth}) => post(
    id,
    parent: parentOf(id),
    replyCount: descendants(id),
    depth: depth,
    parentPost: parentOf(id) == 0 || !inlineParents
        ? null
        : post(parentOf(id), parent: parentOf(parentOf(id)), replyCount: descendants(parentOf(id))),
  );

  http.Client get client => MockClient((request) async {
    final id = int.parse(RegExp(r'/posts/(\d+)/replies').firstMatch(request.url.path)![1]!);
    final depth = int.parse(request.url.queryParameters['depth'] ?? '1');
    final limit = int.parse(request.url.queryParameters['limit'] ?? '20');
    asked.add('$id@$depth');

    final found = <Map<String, dynamic>>[];
    void walk(int parent, int level) {
      if (level > depth) return;
      for (final child in children[parent] ?? const <int>[]) {
        found.add(asJson(child, depth: level));
        walk(child, level + 1);
      }
    }
    walk(id, 1);

    found.sort((a, b) => (b['id'] as int).compareTo(a['id'] as int));
    return http.Response(
      jsonEncode({
        'data': found.take(limit).toList(),
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

/// Every node, flattened, with the depth it was drawn at.
List<({ReplyNode node, int depth})> flatten(List<ReplyNode> nodes, [int depth = 1]) => [
  for (final node in nodes) ...[
    (node: node, depth: depth),
    ...flatten(node.children, depth + 1),
  ],
];

void main() {
  group('"+N more replies"', () {
    test('offers to load in place right up to the nesting cap, and not past it', () async {
      // A chain deeper than the app nests. Each open reaches [threadFetchDepth]
      // levels, so walking to the bottom is a few deliberate taps — and the node that
      // lands *on* the cap must stop offering, because there is nowhere to draw what
      // it would load. Offering there fired a request and changed nothing.
      final server = FakeThread({for (var id = 1; id < 12; id++) id: [id + 1]});
      final container = server.container();

      var nodes = flatten(await container.read(threadProvider(1).future));
      expect(nodes, hasLength(threadFetchDepth), reason: 'two levels on the first open');
      expect(nodes.last.node.expandable, isTrue, reason: 'short of the cap: load here');

      // Walk down until a node sits on the cap.
      while (nodes.last.depth < maxThreadDepth) {
        await container.read(threadProvider(1).notifier).expand(nodes.last.node.post.id);
        nodes = flatten(await container.read(threadProvider(1).future));
      }

      expect(nodes, hasLength(maxThreadDepth));
      expect(nodes.every((entry) => entry.node.hasUnloaded), isTrue);
      expect(
        nodes.last.node.expandable,
        isFalse,
        reason: 'nothing can be revealed in place at the cap; this opens the post',
      );
    });

    test('counts descendants, not direct children', () async {
      // reply_count is a whole descendant count. Comparing it against the number of
      // *direct* children advertised replies that were already on screen.
      final server = FakeThread({for (var id = 1; id < 12; id++) id: [id + 1]});
      final tree = await server.container().read(threadProvider(1).future);

      // Node 2 has descendants 3..12 (ten), of which only 3 is drawn beneath it.
      final top = tree.single;
      expect(top.post.id, 2);
      expect(top.unloaded, server.descendants(2) - countReplies(top.children));
      expect(top.unloaded, 9);
    });

    test('does load in place when a cached branch was invalidated', () async {
      // Ids only ever go up, so a node that made it onto the page always brings its
      // descendants with it — the page can never split a node from its own children.
      // Loading in place is therefore for one case only: a branch whose cached
      // replies were dropped because the server reported a different count.
      final server = FakeThread({for (var id = 1; id < 12; id++) id: [id + 1]});
      final container = server.container();
      await container.read(threadProvider(1).future);

      // What a live reply arriving for node 3 does.
      container.read(repliesCacheProvider).forget(3);
      container.invalidate(threadProvider(1));

      var tree = await container.read(threadProvider(1).future);
      final three = flatten(tree).firstWhere((entry) => entry.node.post.id == 3).node;
      expect(three.children, isEmpty, reason: 'its replies were dropped');
      expect(three.expandable, isTrue, reason: 'and there is room to draw them again');

      final before = server.asked.length;
      await container.read(threadProvider(1).notifier).expand(3);
      tree = container.read(threadProvider(1)).value!;

      expect(server.asked.length, before + 1, reason: 'one request, not a storm');
      final expanded = flatten(tree).firstWhere((entry) => entry.node.post.id == 3).node;
      expect(expanded.children, isNotEmpty, reason: 'the tap visibly did something');
      expect(expanded.expandable, isFalse);
    });

    test('asking twice costs nothing', () async {
      final server = FakeThread({for (var id = 1; id < 12; id++) id: [id + 1]});
      final container = server.container();
      await container.read(threadProvider(1).future);
      container.read(repliesCacheProvider).forget(3);
      container.invalidate(threadProvider(1));
      await container.read(threadProvider(1).future);

      await container.read(threadProvider(1).notifier).expand(3);
      final after = server.asked.length;
      await container.read(threadProvider(1).notifier).expand(3);

      expect(server.asked.length, after);
    });
  });

  group('cached replies', () {
    test('survive a count that only looks different', () async {
      // reply_count is a whole descendant count. Comparing it against the number of
      // direct children held meant nearly every node with a grandchild was treated
      // as stale, and its replies were thrown away on every feed fetch.
      final server = FakeThread({for (var id = 1; id < 12; id++) id: [id + 1]});
      final container = server.container();
      await container.read(threadProvider(1).future);
      final cache = container.read(repliesCacheProvider);
      expect(cache[2], isNotNull);

      // Exactly what a feed or the firehose hands it: the same posts, unchanged.
      cache.noticeCounts([
        for (final entry in [2, 3, 4, 5]) Post.fromJson(server.asJson(entry)),
      ]);

      expect(cache[2], isNotNull, reason: 'nothing changed, so nothing is dropped');
      final before = server.asked.length;
      container.invalidate(threadProvider(1));
      await container.read(threadProvider(1).future);
      expect(server.asked.length, before, reason: 'and reopening costs no request');
    });

    test('are dropped when the count really did change', () async {
      final server = FakeThread({for (var id = 1; id < 12; id++) id: [id + 1]});
      final container = server.container();
      await container.read(threadProvider(1).future);
      final cache = container.read(repliesCacheProvider);

      final grown = Post.fromJson({...server.asJson(2), 'reply_count': 99});
      cache.noticeCounts([grown]);

      expect(cache[2], isNull, reason: 'the subtree grew, so what we hold is wrong');
    });
  });

  group('a page whose newest replies are all deep', () {
    test('is repaired from the inlined parents, for free', () async {
      // The newest hundred are all in one busy branch, so that branch\'s own parent
      // falls off the page. Placing by parent_id alone dropped every one of them and
      // a thread with a hundred and twenty replies rendered as empty.
      final server = FakeThread({
        1: [2, 200],
        2: [3, 4, 5],
        200: [for (var id = 300; id < 420; id++) id],
      });
      final container = server.container();

      final tree = await container.read(threadProvider(1).future);

      expect(tree, isNotEmpty, reason: 'a thread with replies must never render empty');
      expect(
        server.asked,
        ['1@$threadFetchDepth'],
        reason: 'the inlined parent is already in the response; no second request',
      );
      // Node 200 was rebuilt from the parent its children carry.
      final rebuilt = tree.firstWhere((node) => node.post.id == 200);
      expect(rebuilt.children, isNotEmpty);
    });

    test('falls back to one direct-children request when it cannot be repaired', () async {
      // The page is all one busy branch, and this server does not inline the parent
      // that would place it. Nothing in the response can hang off the root.
      final server = FakeThread({
        1: [2, 200],
        200: [for (var id = 300; id < 420; id++) id],
      }, inlineParents: false);
      final container = server.container();

      final tree = await container.read(threadProvider(1).future);

      expect(tree, isNotEmpty, reason: 'better one more request than an empty thread');
      expect(server.asked, ['1@$threadFetchDepth', '1@1']);
      expect(tree.map((node) => node.post.id), [2, 200]);
    });
  });

  test('a thread that really has no replies asks once and renders nothing', () async {
    final server = FakeThread(const {});
    expect(await server.container().read(threadProvider(1).future), isEmpty);
    expect(
      server.asked,
      ['1@$threadFetchDepth'],
      reason: 'no fallback for a genuinely empty thread',
    );
  });
}
