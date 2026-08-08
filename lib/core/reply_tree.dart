/// Turning a set of fetched reply pages into a tree.
///
/// `/posts/{id}/replies` returns **direct children only**, so a thread is assembled
/// from one request per branching node. Every post carries `reply_count`, which is
/// what lets us know a node has children — and how many we did not load — without
/// spending a request to find out.
library;

import 'models.dart';

final class ReplyNode {
  const ReplyNode({required this.post, required this.children, required this.unloaded});

  final Post post;
  final List<ReplyNode> children;

  /// Replies known to exist but not fetched, because the depth cap or the request
  /// budget stopped us. Drives the "N more replies" link.
  final int unloaded;

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
    for (final post in replies)
      if (depth >= maxDepth || !loaded.containsKey(post.id))
        ReplyNode(post: post, children: const [], unloaded: post.replyCount)
      else
        () {
          final children = assembleReplies(
            post.id,
            loaded,
            maxDepth: maxDepth,
            depth: depth + 1,
          );
          return ReplyNode(
            post: post,
            children: children,
            // The server may report more replies than the page we asked for.
            unloaded: (post.replyCount - children.length).clamp(0, post.replyCount),
          );
        }(),
  ];
}

/// Total posts in a tree, used to say how much is on screen.
int countReplies(List<ReplyNode> nodes) =>
    nodes.fold(0, (total, node) => total + 1 + countReplies(node.children));
