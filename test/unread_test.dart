import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/feed_tree.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/unread.dart';

Post post(int id, {bool? unread, int? parentId}) => Post(
  id: id,
  body: 'post $id',
  createdAt: DateTime(2026, 8, 26),
  parentId: parentId,
  replyCount: 0,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/$id'),
  author: Author(handle: 'a', url: Uri.parse('https://textlog.cc/u/a')),
  unread: unread,
);

void main() {
  group('the catch-up set', () {
    test('keeps the newest few unread and reads the rest', () {
      final page = [for (var id = 20; id >= 1; id--) post(id, unread: true)];
      final capped = capUnread(page, budget: 3);

      expect(capped.unread, 3);
      expect(capped.posts.where((p) => p.unread == true).map((p) => p.id), [20, 19, 18]);
    });

    test('leaves a short feed alone', () {
      final page = [post(3, unread: true), post(2, unread: false), post(1, unread: true)];
      final capped = capUnread(page, budget: unreadCatchUp);

      expect(capped.unread, 2);
      expect(capped.posts, same(page), reason: 'nothing to cap, nothing to copy');
    });

    test('a spent budget reads everything', () {
      final capped = capUnread([post(1, unread: true)], budget: 0);
      expect(capped.unread, 0);
      expect(capped.posts.single.unread, isFalse);
    });

    test('posts with no unread state are untouched', () {
      // Every feed but the latest one: `unread` is null there, which is not the
      // same as read and must not be turned into it.
      final capped = capUnread([post(1), post(2)], budget: 0);
      expect(capped.posts.every((p) => p.unread == null), isTrue);
    });
  });

  group('a block of posts', () {
    test('counts the replies grouped under it, not just the top', () {
      // The feed joins replies to parents on the same page, so one block on screen
      // can hold several unread posts — and scrolling past it passes all of them.
      final threads = groupFeed([
        post(3, unread: true, parentId: 1),
        post(2, unread: true, parentId: 1),
        post(1, unread: true),
      ]);

      expect(threads.single.root.id, 1);
      expect(unreadIn(threads.single)..sort(), [1, 2, 3]);
    });

    test('and only the unread ones', () {
      final threads = groupFeed([
        post(2, unread: false, parentId: 1),
        post(1, unread: true),
      ]);
      expect(unreadIn(threads.single), [1]);
    });

    test('nothing unread is nothing to mark', () {
      final threads = groupFeed([post(1, unread: false)]);
      expect(unreadIn(threads.single), isEmpty);
    });
  });
}
