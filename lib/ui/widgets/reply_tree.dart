import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locks.dart';
import '../../core/reply_tree.dart';
import '../../state/thread.dart';
import '../router.dart';
import '../theme.dart';
import 'post_actions.dart';
import 'link_preview_view.dart';
import 'poll_view.dart';
import 'translatable_body.dart';
import 'post_tile.dart';
import 'todo_view.dart';
import 'post_meta.dart';
import 'pressable.dart';

/// `.reply-branch` — siblings share one hairline rail, indented by a gutter.
class ReplyBranch extends StatelessWidget {
  const ReplyBranch(
    this.nodes, {
    super.key,
    this.rootId,
    this.depth = 1,
    this.lockedAbove = false,
  });

  final List<ReplyNode> nodes;

  /// The thread these replies belong to, so a branch can ask it to load more.
  ///
  /// Null inside a feed, where the tree is only what that page happened to return
  /// and there is no thread notifier to ask — so "read more" opens the post instead
  /// of loading in place.
  final int? rootId;

  /// How deep this branch sits, counting the thread's own post as zero.
  final int depth;

  /// An ancestor carried `#lock`, so nothing under it can be replied to. Passed down
  /// rather than recomputed, because a reply cannot see past its own parent.
  final bool lockedAbove;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(left: replyIndentOf(context)),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: context.palette.soft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final node in nodes)
            _Node(node, rootId: rootId, depth: depth, lockedAbove: lockedAbove),
        ],
      ),
    );
  }
}

class _Node extends ConsumerStatefulWidget {
  const _Node(
    this.node, {
    required this.rootId,
    required this.depth,
    required this.lockedAbove,
  });

  final ReplyNode node;
  final int? rootId;
  final int depth;
  final bool lockedAbove;

  @override
  ConsumerState<_Node> createState() => _NodeState();
}

class _NodeState extends ConsumerState<_Node> {
  var _folded = false;

  @override
  Widget build(BuildContext context) {
    final node = widget.node;
    final theme = Theme.of(context).textTheme;
    final meta = theme.bodySmall!;
    final foldable = node.children.isNotEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // `.reply-node > .post`
        Padding(
          padding: EdgeInsets.only(
            left: space2,
            right: gutterOf(context),
            top: space2,
            bottom: space3,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostContextLine(
                post: node.post,
                style: meta,
                showReplyCount: false,
                // This row is the accordion's header. If it reflows, the fold
                // control drops onto a second line and the whole thing reads broken.
                singleLine: true,
                onTap: () => openPost(context, node.post.id),
                trailing: [
                  if (foldable) _Fold(_folded, () => setState(() => _folded = !_folded)),
                ],
              ),
              const SizedBox(height: space2),
              TranslatableBody(node.post),
              PollView(node.post),
              TodoView(node.post),
              LinkPreviews(node.post),
              const SizedBox(height: space3),
              Row(
                children: postActions(
                  context,
                  ref,
                  node.post,
                  style: meta,
                  locked: widget.lockedAbove || locksThread(node.post),
                ),
              ),
            ],
          ),
        ),
        if (!_folded) ...[
          ReplyBranch(
            node.children,
            rootId: widget.rootId,
            depth: widget.depth + 1,
            lockedAbove: widget.lockedAbove || locksThread(node.post),
          ),
          if (node.hasUnloaded) _More(node, rootId: widget.rootId, depth: widget.depth),
        ],
      ],
    );
  }
}

/// Replies this branch has not asked for yet. Tapping loads them here; past the
/// nesting cap there is nowhere to draw them, so it opens the post instead.
class _More extends ConsumerStatefulWidget {
  const _More(this.node, {required this.rootId, required this.depth});

  final ReplyNode node;
  final int? rootId;
  final int depth;

  @override
  ConsumerState<_More> createState() => _MoreState();
}

/// `−` open, `+` folded, as the site does, boxed so it reads as a control rather
/// than a stray character in the meta line.
class _Fold extends StatelessWidget {
  const _Fold(this.folded, this.onTap);

  final bool folded;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = Theme.of(context).textTheme.bodySmall!;

    return Pressable(
      onTap: onTap,
      semanticLabel: folded ? 'expand replies' : 'fold replies',
      builder: (context, pressed) => Container(
        // Fixed, so `+` and `−` do not resize the control as it toggles.
        width: 24,
        height: 22,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: pressed ? palette.tagBg : Colors.transparent,
          border: Border.all(color: pressed ? palette.accent : palette.soft),
        ),
        child: Text(
          folded ? '+' : '−',
          textAlign: TextAlign.center,
          style: meta.copyWith(
            color: pressed ? palette.accent : palette.muted,
            height: 1,
          ),
        ),
      ),
    );
  }
}

class _MoreState extends ConsumerState<_More> {
  var _loading = false;

  Future<void> _load() async {
    final rootId = widget.rootId;
    if (rootId == null) return;
    setState(() => _loading = true);
    try {
      await ref.read(threadProvider(rootId).notifier).expand(widget.node.post.id);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final count = widget.node.unloaded;
    // In a feed the tree is only what that page returned, so a count of what is
    // missing is noise — the thread is one tap away and says it properly.
    final inFeed = widget.rootId == null;
    final label = inFeed
        ? 'read more'
        : '+ $count more ${count == 1 ? 'reply' : 'replies'}';

    // Only load in place when that will actually put something on screen. It used
    // to try regardless, which meant a tap past the nesting cap — or on a node whose
    // replies were already loaded — spent a request and changed nothing at all.
    final loadHere = !inFeed && widget.node.expandable;

    return Padding(
      padding: EdgeInsets.only(left: space2 + replyIndentOf(context), bottom: space3),
      child: Pressable(
        onTap: _loading
            ? null
            : loadHere
            ? _load
            : () => openPost(context, widget.node.post.id),
        builder: (context, pressed) => Text(
          _loading ? 'loading…' : label,
          style: Theme.of(context).textTheme.bodySmall!
              .asLink(palette)
              .copyWith(color: pressed ? palette.accentDark : null),
        ),
      ),
    );
  }
}

/// The same replies with the nesting dropped, in the order they were written.
///
/// The site offers this; on a phone it is arguably the better default for a deep
/// thread, because five levels of rail leaves very little room for the words.
class FlatReplies extends StatelessWidget {
  const FlatReplies(
    this.nodes, {
    super.key,
    required this.rootId,
    this.lockedAbove = false,
  });

  final List<ReplyNode> nodes;
  final int rootId;

  /// The thread's own post carried `#lock`, so none of these can be replied to.
  final bool lockedAbove;

  @override
  Widget build(BuildContext context) {
    // Flattened with the lock carried along: read in order, a post no longer sits
    // under the ancestor that closed it, so it cannot work it out from its position.
    final flattened = <(ReplyNode, bool)>[];
    void visit(List<ReplyNode> branch, {required bool locked}) {
      for (final node in branch) {
        flattened.add((node, locked));
        visit(node.children, locked: locked || locksThread(node.post));
      }
    }
    visit(nodes, locked: lockedAbove);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (node, locked) in flattened)
          PostTile(
            node.post,
            // The parent is somewhere above in the list, so quoting it again would
            // double every post on screen.
            showParent: false,
            lockedAbove: locked,
          ),
      ],
    );
  }
}
