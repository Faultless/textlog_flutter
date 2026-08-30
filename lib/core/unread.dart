/// How much of a feed a fresh start is willing to call unread.
///
/// The latest feed is everything anyone wrote, so an account that has been away for
/// a day comes back to hundreds of unread posts. Marking them read by scrolling —
/// which is the rule this app wants — then means scrolling past all of them, and
/// nobody does that; they press "mark all as read", which is the button the reading
/// rule was supposed to make unnecessary.
///
/// So a fresh start takes a *catch-up set*: the newest [unreadCatchUp] unread posts,
/// and no more. Everything older is shown as read, because for a reader who has been
/// away that is the honest state of it — they are not going to read it. Read the
/// catch-up set and the feed marks the rest read on the server too, in one request.
library;

import 'feed_tree.dart';
import 'models.dart';
import 'reply_tree.dart';

/// The size of the catch-up set. Small enough to be a few flicks of the thumb.
const unreadCatchUp = 12;

/// [posts] with every unread post past [budget] treated as read, and how many were
/// kept unread.
///
/// Order is the feed's, so a newest-first feed keeps the newest — the ones a reader
/// coming back actually wants. Nothing is sent to the server here: the posts outside
/// the budget are read *on this device* until the catch-up set is finished, and it
/// is that which marks the whole feed read.
({List<Post> posts, int unread}) capUnread(
  List<Post> posts, {
  int budget = unreadCatchUp,
}) {
  var left = budget;
  var kept = 0;
  var capped = false;
  final result = <Post>[];

  for (final post in posts) {
    if (post.unread != true) {
      result.add(post);
    } else if (left > 0) {
      left--;
      kept++;
      result.add(post);
    } else {
      capped = true;
      result.add(post.copyWith(read: true));
    }
  }

  return (posts: capped ? result : posts, unread: kept);
}

/// Every unread post id in [thread] — the root and the replies grouped under it.
///
/// A feed page joins replies to parents that are on the same page, so one block on
/// screen can hold several unread posts while only the root carries the rail. Passing
/// the block means passing all of them: they were on screen together, and leaving the
/// replies unread would keep a feed that has visibly been read from ever emptying.
List<int> unreadIn(FeedThread thread) => [
  if (thread.root.unread == true) thread.root.id,
  ...thread.replies.expand(_unreadUnder),
];

Iterable<int> _unreadUnder(ReplyNode node) sync* {
  if (node.post.unread == true) yield node.post.id;
  for (final child in node.children) {
    yield* _unreadUnder(child);
  }
}
