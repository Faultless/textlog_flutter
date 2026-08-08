import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/body_tokens.dart';
import '../../core/reply_tree.dart';
import '../screens/web_action.dart';
import '../theme.dart';
import 'post_body.dart';

/// `.reply-branch` — siblings share one hairline rail, indented by a gutter.
class ReplyBranch extends StatelessWidget {
  const ReplyBranch(this.nodes, {super.key});

  final List<ReplyNode> nodes;

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
        children: [for (final node in nodes) _Node(node)],
      ),
    );
  }
}

class _Node extends ConsumerStatefulWidget {
  const _Node(this.node);

  final ReplyNode node;

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
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: GestureDetector(
                      onTap: () => context.push('/u/${node.post.author.handle}'),
                      child: Text(
                        '@${node.post.author.handle}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: meta.asLink(palette).copyWith(color: palette.ink),
                      ),
                    ),
                  ),
                  const SizedBox(width: space3),
                  GestureDetector(
                    onTap: () => context.push('/post/${node.post.id}'),
                    child: Text(relativeTime(node.post.createdAt), style: meta.asLink(palette)),
                  ),
                  const SizedBox(width: space3),
                  GestureDetector(
                    onTap: () => openReply(ref, node.post.id),
                    child: Text(
                      'reply',
                      style: meta.asLink(palette).copyWith(color: palette.muted),
                    ),
                  ),
                  if (foldable) ...[
                    const SizedBox(width: space1),
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
          ReplyBranch(node.children),
          if (node.hasUnloaded) _More(node),
        ],
      ],
    );
  }
}

/// The depth cap or the request budget stopped here. Opening the post as its own
/// thread continues from this node, which is also a shareable URL.
class _More extends StatelessWidget {
  const _More(this.node);

  final ReplyNode node;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final count = node.unloaded;

    return Padding(
      padding: EdgeInsets.only(left: space3 + gutterOf(context), bottom: space4),
      child: GestureDetector(
        onTap: () => context.push('/post/${node.post.id}'),
        child: Text(
          '+ $count more ${count == 1 ? 'reply' : 'replies'}',
          style: Theme.of(context).textTheme.bodySmall!.asLink(palette),
        ),
      ),
    );
  }
}
