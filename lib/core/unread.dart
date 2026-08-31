/// The catch-up set: how much of a feed a fresh start is willing to call unread.
///
/// Hundreds of unread posts cannot be cleared by scrolling, so only the newest few
/// are offered; finishing them marks the whole feed read.
library;

import 'feed_tree.dart';
import 'models.dart';
import 'reply_tree.dart';

/// A few flicks of the thumb.
const unreadCatchUp = 12;

/// [posts] with every unread post past [budget] treated as read, and how many were
/// kept. Order is the feed's, so a newest-first feed keeps the newest. Nothing is
/// sent to the server here.
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

/// Every unread post id in [thread]. A feed page nests replies under parents, so one
/// block can hold several unread posts while only its root is measured.
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
