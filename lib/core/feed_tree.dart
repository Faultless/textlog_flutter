/// Joining a feed page into threads, so a conversation is not repeated down it.
///
/// A feed that returns twenty replies to the same thread used to render twenty
/// posts, each quoting the same parent underneath it — the reader scrolled past the
/// same words over and over. textlog fixed that on the site by nesting any reply
/// whose parent is *also on the page* under that parent instead.
///
/// It works because the server already gives us everything needed: each post's
/// `parent_id`, and its `parent` inlined for the case where the parent is not on the
/// page. No extra request, and it matters most on a phone, where the duplication was
/// costing the most scrolling.
library;

import 'models.dart';
import 'reply_tree.dart';

/// A root from a feed page, plus whichever of the page's other posts hang off it.
final class FeedThread {
  const FeedThread({required this.root, required this.replies});

  final Post root;

  /// Empty for the ordinary case of a post with nothing else from this page under it.
  final List<ReplyNode> replies;

  bool get isThread => replies.isNotEmpty;
}

/// Group a feed page into threads, preserving the page's order.
///
/// A post is a root when its parent is not on the page — which is every post in a
/// feed of top-level notes, so a feed without conversations comes back unchanged.
///
/// [maxDepth] caps the nesting the way the thread screen does; anything deeper stays
/// under the last node it fits below rather than being dropped.
List<FeedThread> groupFeed(List<Post> posts, {int maxDepth = 5}) {
  if (posts.isEmpty) return const [];

  final onPage = {for (final post in posts) post.id: post};
  final children = <int, List<Post>>{};
  final depth = <int, int>{};
  final isRoot = <int>{};

  // Ascending id order, so a parent is always assigned before its children — the
  // server hands out ids in order, and it makes a single pass enough.
  final byId = [...posts]..sort((a, b) => a.id.compareTo(b.id));

  for (final post in byId) {
    final parentId = post.parentId;
    final parentDepth = parentId == null ? null : depth[parentId];

    // A root when the parent is not on this page — or when nesting it would go
    // past the cap, in which case it starts a block of its own. Dropping it
    // instead would silently lose posts out of the middle of a long conversation,
    // and a parent that has not been assigned yet means the ids are not ordered
    // the way the server orders them, which is the same situation.
    if (parentId == null || !onPage.containsKey(parentId) || parentDepth == null
        || parentDepth + 1 > maxDepth) {
      depth[post.id] = 0;
      isRoot.add(post.id);
      continue;
    }
    depth[post.id] = parentDepth + 1;
    (children[parentId] ??= []).add(post);
  }

  // Oldest first inside a thread: a conversation reads down the page, even though
  // the feed itself is newest first.
  for (final branch in children.values) {
    branch.sort((a, b) => a.id.compareTo(b.id));
  }

  return [
    // Roots in the order the feed returned them, not in id order.
    for (final post in posts)
      if (isRoot.contains(post.id))
        FeedThread(root: post, replies: _branch(post.id, children)),
  ];
}

/// The page's own posts, nested. The depth cap was already applied when the roots
/// were chosen, so this only has to follow the map it was given.
List<ReplyNode> _branch(int parentId, Map<int, List<Post>> children) => [
  for (final post in children[parentId] ?? const <Post>[])
    ReplyNode(
      post: post,
      children: _branch(post.id, children),
      // Replies this page does not carry. A feed page holds a handful of a thread's
      // replies, so this is usually most of them — it drives a "read more" link
      // into the thread rather than a count nobody asked for.
      unloaded: _missing(post, children),
    ),
];

int _missing(Post post, Map<int, List<Post>> children) {
  final held = children[post.id]?.length ?? 0;
  return (post.replyCount - held).clamp(0, post.replyCount);
}

/// How many of the page's posts a thread accounts for, so a caller can tell whether
/// grouping actually changed anything.
int countThreadPosts(List<FeedThread> threads) =>
    threads.fold(0, (total, thread) => total + 1 + countReplies(thread.replies));
