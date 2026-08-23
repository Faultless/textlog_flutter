import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/feed_tree.dart';
import 'package:textlog/core/models.dart';

Post post(int id, {int? parentId, int replyCount = 0, String handle = 'a', Post? parent}) => Post(
  id: id,
  body: 'post $id',
  createdAt: DateTime(2026, 8, 8).add(Duration(minutes: id)),
  parentId: parentId ?? parent?.id,
  replyCount: replyCount,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/$id'),
  author: Author(handle: handle, url: Uri.parse('https://textlog.cc/u/$handle')),
  parent: parent,
);

/// Ids in the order they would be drawn, roots and their nesting flattened.
List<int> drawn(List<FeedThread> threads) {
  final ids = <int>[];
  void walk(List nodes) {
    for (final node in nodes) {
      ids.add(node.post.id as int);
      walk(node.children as List);
    }
  }
  for (final thread in threads) {
    ids.add(thread.root.id);
    walk(thread.replies);
  }
  return ids;
}

void main() {
  test('a feed of top-level notes is unchanged', () {
    final threads = groupFeed([post(3), post(2), post(1)]);
    expect(threads, hasLength(3));
    expect(threads.every((thread) => !thread.isThread), isTrue);
    expect(drawn(threads), [3, 2, 1]);
  });

  test('a reply whose parent is on the page nests under it', () {
    // The whole point: this used to render as two posts, the second quoting the
    // first underneath it.
    final threads = groupFeed([post(2, parentId: 1), post(1, replyCount: 1)]);
    expect(threads, hasLength(1));
    expect(threads.single.root.id, 1);
    expect(threads.single.replies.single.post.id, 2);
  });

  test('a reply whose parent is not on the page stays a root', () {
    // It keeps its quoted parent, which is the only context the reader gets.
    final threads = groupFeed([post(2, parentId: 99, parent: post(99))]);
    expect(threads, hasLength(1));
    expect(threads.single.root.id, 2);
    expect(threads.single.isThread, isFalse);
  });

  test('a whole conversation on one page becomes one block', () {
    final threads = groupFeed([
      post(4, parentId: 3),
      post(3, parentId: 2),
      post(2, parentId: 1),
      post(1, replyCount: 3),
    ]);
    expect(threads, hasLength(1));
    expect(drawn(threads), [1, 2, 3, 4]);
  });

  test('siblings read oldest first inside a thread', () {
    // The feed is newest first; a conversation is not.
    final threads = groupFeed([
      post(4, parentId: 1),
      post(3, parentId: 1),
      post(2, parentId: 1),
      post(1, replyCount: 3),
    ]);
    expect(drawn(threads), [1, 2, 3, 4]);
  });

  test('the page order of roots is kept', () {
    final threads = groupFeed([
      post(10),
      post(5, parentId: 4),
      post(4, replyCount: 1),
      post(1),
    ]);
    expect(threads.map((thread) => thread.root.id), [10, 4, 1]);
    expect(drawn(threads), [10, 4, 5, 1]);
  });

  test('nothing is lost or duplicated', () {
    final posts = [
      post(9),
      post(8, parentId: 7),
      post(7, parentId: 6, replyCount: 1),
      post(6, replyCount: 2),
      post(5, parentId: 99, parent: post(99)),
    ];
    final threads = groupFeed(posts);
    expect(countThreadPosts(threads), posts.length);
    expect(drawn(threads)..sort(), posts.map((post) => post.id).toList()..sort());
  });

  test('nesting stops at the depth cap without losing the deeper posts', () {
    // A ten-deep chain on one page. Everything is still drawn; the chain just
    // restarts as a new block each time it would nest past the cap.
    final posts = [for (var id = 10; id >= 1; id--) post(id, parentId: id == 1 ? null : id - 1)];
    final threads = groupFeed(posts, maxDepth: 3);

    expect(countThreadPosts(threads), posts.length, reason: 'nothing may be dropped');
    expect(drawn(threads)..sort(), [for (var id = 1; id <= 10; id++) id]);
    // Four levels per block: the root and three under it.
    expect(threads.length, 3);
  });

  test('a very deep page never nests past the cap', () {
    final posts = [for (var id = 30; id >= 1; id--) post(id, parentId: id == 1 ? null : id - 1)];
    for (final threads in [groupFeed(posts, maxDepth: 5), groupFeed(posts)]) {
      expect(countThreadPosts(threads), posts.length);
      var deepest = 0;
      void walk(List nodes, int depth) {
        if (nodes.isEmpty) return;
        deepest = depth > deepest ? depth : deepest;
        for (final node in nodes) {
          walk(node.children as List, depth + 1);
        }
      }
      for (final thread in threads) {
        walk(thread.replies, 1);
      }
      expect(deepest, lessThanOrEqualTo(5));
    }
  });

  test('a node with replies the page does not hold advertises them', () {
    // Drives the "read more" link into the thread.
    final threads = groupFeed([post(2, parentId: 1, replyCount: 7), post(1, replyCount: 8)]);
    expect(threads.single.replies.single.unloaded, 7);
  });

  test('a node whose replies are all on the page advertises nothing', () {
    final threads = groupFeed([
      post(3, parentId: 2),
      post(2, parentId: 1, replyCount: 1),
      post(1, replyCount: 2),
    ]);
    expect(threads.single.replies.single.unloaded, 0);
  });

  test('an empty page groups to nothing', () {
    expect(groupFeed(const []), isEmpty);
  });

  test('a cycle cannot hang the grouper or swallow the page', () {
    // Not something the server can produce — ids only go up — but losing a whole
    // page to malformed data would be far worse than rendering it flat.
    final threads = groupFeed([post(1, parentId: 2), post(2, parentId: 1)], maxDepth: 5);
    expect(countThreadPosts(threads), 2);
    expect(drawn(threads)..sort(), [1, 2]);
  });
}
