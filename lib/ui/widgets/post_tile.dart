import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/body_tokens.dart';
import '../../core/models.dart';
import '../screens/web_action.dart';
import '../theme.dart';
import 'parent_quote.dart';
import 'post_body.dart';

/// `.post` — 24px/gutter padding, hairline top rule, `@handle` and an accent
/// timestamp above the body, and the quoted parent beneath it when this is a reply.
class PostTile extends ConsumerWidget {
  const PostTile(this.post, {super.key, this.showTopBorder = true});

  final Post post;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final meta = Theme.of(context).textTheme.bodySmall!;

    return InkWell(
      onTap: () => context.push('/post/${post.id}'),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
        decoration: BoxDecoration(
          border: Border(
            top: showTopBorder ? BorderSide(color: palette.soft) : BorderSide.none,
          ),
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
                    onTap: () => context.push('/u/${post.author.handle}'),
                    child: Text(
                      '@${post.author.handle}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: meta.asLink(palette).copyWith(color: palette.ink),
                    ),
                  ),
                ),
                const SizedBox(width: space4),
                Text(
                  relativeTime(post.createdAt) +
                      (post.replyCount > 0
                          ? ' · ${post.replyCount} ${post.replyCount == 1 ? 'reply' : 'replies'}'
                          : ''),
                  style: meta.asLink(palette),
                ),
                const SizedBox(width: space4),
                GestureDetector(
                  onTap: () => openReply(ref, post.id),
                  child: Text(
                    'reply',
                    style: meta.asLink(palette).copyWith(color: palette.muted),
                  ),
                ),
              ],
            ),
            const SizedBox(height: space3),
            PostBody(post.body),
            if (post.parentId case final parentId?) ParentQuote(parentId),
          ],
        ),
      ),
    );
  }
}
