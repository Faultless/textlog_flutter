import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/reply_tree.dart';

Post post(int id, {int parent = 0, int replyCount = 0}) => Post(
  id: id,
  body: 'post $id',
  createdAt: DateTime(2026, 8, 8),
  parentId: parent == 0 ? null : parent,
  replyCount: replyCount,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/$id'),
  author: Author(handle: 'a', url: Uri.parse('https://textlog.cc/u/a')),
);

void main() {
  test('a flat thread becomes a flat list', () {
    final tree = assembleReplies(1, {
      1: [post(2, parent: 1), post(3, parent: 1)],
    }, maxDepth: 5);

    expect(tree.map((n) => n.post.id), [2, 3]);
    expect(tree.every((n) => n.children.isEmpty), isTrue);
    expect(tree.every((n) => n.hasUnloaded), isFalse);
  });

  test('children nest under their parent', () {
    final tree = assembleReplies(1, {
      1: [post(2, parent: 1, replyCount: 1)],
      2: [post(3, parent: 2, replyCount: 1)],
      3: [post(4, parent: 3)],
    }, maxDepth: 5);

    expect(tree.single.post.id, 2);
    expect(tree.single.children.single.post.id, 3);
    expect(tree.single.children.single.children.single.post.id, 4);
    expect(countReplies(tree), 3);
  });

  test('the depth cap stops nesting and reports the rest as unloaded', () {
    final tree = assembleReplies(1, {
      1: [post(2, parent: 1, replyCount: 1)],
      2: [post(3, parent: 2, replyCount: 4)],
      3: [post(4, parent: 3)],
    }, maxDepth: 2);

    final deepest = tree.single.children.single;
    expect(deepest.post.id, 3);
    expect(deepest.children, isEmpty, reason: 'depth 2 is the cap');
    expect(deepest.unloaded, 4, reason: 'all four are still out there');
  });

  test('a node whose replies were never fetched reports them all as unloaded', () {
    // Budget ran out: post 2 says it has 3 replies but there is no entry for it.
    final tree = assembleReplies(1, {
      1: [post(2, parent: 1, replyCount: 3)],
    }, maxDepth: 5);

    expect(tree.single.children, isEmpty);
    expect(tree.single.unloaded, 3);
  });

  test('a partially fetched node reports only the remainder', () {
    // The server says 5 replies; we fetched a page containing 2.
    final tree = assembleReplies(1, {
      1: [post(2, parent: 1, replyCount: 5)],
      2: [post(3, parent: 2), post(4, parent: 2)],
    }, maxDepth: 5);

    expect(tree.single.children.length, 2);
    expect(tree.single.unloaded, 3);
  });

  test('a stale reply_count never yields a negative remainder', () {
    final tree = assembleReplies(1, {
      1: [post(2, parent: 1, replyCount: 1)],
      2: [post(3, parent: 2), post(4, parent: 2)],
    }, maxDepth: 5);

    expect(tree.single.unloaded, 0);
    expect(tree.single.hasUnloaded, isFalse);
  });

  test('an unknown root is an empty thread, not a crash', () {
    expect(assembleReplies(99, const {}, maxDepth: 5), isEmpty);
  });
}
