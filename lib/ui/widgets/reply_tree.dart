import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/reply_tree.dart';
import '../../state/thread.dart';
import '../theme.dart';
import 'post_actions.dart';
import 'poll_view.dart';
import 'post_body.dart';
import 'post_meta.dart';
import 'pressable.dart';

/// `.reply-branch` — siblings share one hairline rail, indented by a gutter.
class ReplyBranch extends StatelessWidget {
  const ReplyBranch(this.nodes, {super.key, required this.rootId, this.depth = 1});

  final List<ReplyNode> nodes;

  /// The thread these replies belong to, so a branch can ask it to load more.
  final int rootId;

  /// How deep this branch sits, counting the thread's own post as zero.
  final int depth;

  @override
  Widget build(BuildContext context) {
    if (nodes.isEmpty) return const SizedBox.shrink();

    return Container(
      margin: EdgeInsets.only(left: gutterOf(context)),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: context.palette.soft)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [for (final node in nodes) _Node(node, rootId: rootId, depth: depth)],
      ),
    );
  }
}

class _Node extends ConsumerStatefulWidget {
  const _Node(this.node, {required this.rootId, required this.depth});

  final ReplyNode node;
  final int rootId;
  final int depth;

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
            left: space3,
            right: gutterOf(context),
            top: space3,
            bottom: space4,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostContextLine(
                post: node.post,
                style: meta,
                showReplyCount: false,
                onTap: () => context.push('/post/${node.post.id}'),
                trailing: [
                  if (foldable) _Fold(_folded, () => setState(() => _folded = !_folded)),
                ],
              ),
              const SizedBox(height: space2),
              PostBody(node.post.body),
              PollView(node.post),
              const SizedBox(height: space3),
              Row(children: postActions(context, ref, node.post, style: meta)),
            ],
          ),
        ),
        if (!_folded) ...[
          ReplyBranch(node.children, rootId: widget.rootId, depth: widget.depth + 1),
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
  final int rootId;
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
        width: 22,
        height: 20,
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
    setState(() => _loading = true);
    try {
      await ref.read(threadProvider(widget.rootId).notifier).expand(widget.node.post.id);
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final count = widget.node.unloaded;
    final replies = '$count more ${count == 1 ? 'reply' : 'replies'}';
    final canLoadHere = widget.depth < maxThreadDepth;

    return Padding(
      padding: EdgeInsets.only(left: space3 + gutterOf(context), bottom: space4),
      child: Pressable(
        onTap: _loading
            ? null
            : canLoadHere
            ? _load
            : () => context.push('/post/${widget.node.post.id}'),
        builder: (context, pressed) => Text(
          _loading ? 'loading…' : '+ $replies',
          style: Theme.of(context).textTheme.bodySmall!
              .asLink(palette)
              .copyWith(color: pressed ? palette.accentDark : null),
        ),
      ),
    );
  }
}
