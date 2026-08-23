/// Turning a set of fetched reply pages into a tree.
///
/// `/posts/{id}/replies` returns **direct children only**, so a thread is assembled
/// from one request per branching node. Every post carries `reply_count`, which is
/// what lets us know a node has children — and how many we did not load — without
/// spending a request to find out.
library;

import 'models.dart';

final class ReplyNode {
  const ReplyNode({
    required this.post,
    required this.children,
    required this.unloaded,
    this.expandable = false,
  });

  final Post post;
  final List<ReplyNode> children;

  /// Descendants that exist but are not drawn here.
  ///
  /// Compared like with like: the server's `reply_count` is a post's *whole*
  /// descendant count, so this is that minus everything rendered beneath this node —
  /// not minus its direct children, which was comparing two different things and
  /// advertising replies that were already on screen.
  final int unloaded;

  /// Whether fetching this node's replies would actually add children *here*.
  ///
  /// False when its children are already loaded, and false at the nesting cap —
  /// where there is nowhere left to draw them, so the honest move is to open the
  /// post and give the reader five fresh levels from there.
  ///
  /// This is the difference between a "+N more" that works and one that fires a
  /// request and changes nothing, which is what it used to do.
  final bool expandable;

  bool get hasUnloaded => unloaded > 0;
}

/// Pure: fetched pages in, tree out. [loaded] maps a post id to its direct replies.
///
/// A node at [maxDepth], or one whose replies were never fetched, keeps its children
/// empty and reports them all as [ReplyNode.unloaded].
List<ReplyNode> assembleReplies(
  int parentId,
  Map<int, List<Post>> loaded, {
  required int maxDepth,
  int depth = 1,
}) {
  final replies = loaded[parentId];
  if (replies == null) return const [];

  return [
    for (final post in replies) _node(post, loaded, maxDepth: maxDepth, depth: depth),
  ];
}

ReplyNode _node(
  Post post,
  Map<int, List<Post>> loaded, {
  required int maxDepth,
  required int depth,
}) {
  // At the cap there is no room to nest, whatever we hold.
  final atCap = depth >= maxDepth;
  final fetched = loaded.containsKey(post.id);
  final children = atCap || !fetched
      ? const <ReplyNode>[]
      : assembleReplies(post.id, loaded, maxDepth: maxDepth, depth: depth + 1);

  return ReplyNode(
    post: post,
    children: children,
    // Whole descendant count against whole rendered count.
    unloaded: (post.replyCount - countReplies(children)).clamp(0, post.replyCount),
    expandable: !atCap && !fetched && post.replyCount > 0,
  );
}

/// Total posts in a tree, used to say how much is on screen.
int countReplies(List<ReplyNode> nodes) =>
    nodes.fold(0, (total, node) => total + 1 + countReplies(node.children));
