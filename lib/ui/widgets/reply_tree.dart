import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/body_tokens.dart';
import '../../core/reply_tree.dart';
import '../../state/thread.dart';
import '../theme.dart';
import 'post_actions.dart';
import 'post_body.dart';

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
    final palette = context.palette;
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
              Wrap(
                spacing: space3,
                runSpacing: space2,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  GestureDetector(
                    onTap: () => context.push('/u/${node.post.author.handle}'),
                    child: Text(
                      '@${node.post.author.handle}',
                      style: meta.asLink(palette).copyWith(color: palette.ink),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => context.push('/post/${node.post.id}'),
                    child: Text(relativeTime(node.post.createdAt), style: meta.asLink(palette)),
                  ),
                  ...postActions(context, ref, node.post, style: meta),
                  if (foldable) ...[
                    // `container: true` or Flutter merges this into the reply's
                    // text and the control disappears for screen readers.
                    Semantics(
                      container: true,
                      button: true,
                      excludeSemantics: true,
                      label: _folded ? 'expand replies' : 'fold replies',
                      child: GestureDetector(
                        onTap: () => setState(() => _folded = !_folded),
                        behavior: HitTestBehavior.opaque,
                        child: Padding(
                          // A single glyph is far too small a target on a phone.
                          padding: const EdgeInsets.symmetric(horizontal: space2),
                          child: Text(
                            // `−` open, `+` folded, as the site does.
                            _folded ? '+' : '−',
                            style: meta.copyWith(color: palette.muted),
                          ),
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(height: space2),
              PostBody(node.post.body),
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
      child: GestureDetector(
        onTap: _loading
            ? null
            : canLoadHere
            ? _load
            : () => context.push('/post/${widget.node.post.id}'),
        behavior: HitTestBehavior.opaque,
        child: Text(
          _loading ? 'loading…' : '+ $replies',
          style: Theme.of(context).textTheme.bodySmall!.asLink(palette),
        ),
      ),
    );
  }
}
