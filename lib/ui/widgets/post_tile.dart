import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/body_tokens.dart';
import '../../core/models.dart';
import '../theme.dart';
import 'parent_quote.dart';
import 'post_actions.dart';
import 'post_body.dart';

/// `.post` — 24px/gutter padding, hairline top rule, `@handle` and an accent
/// timestamp above the body, and the quoted parent beneath it when this is a reply.
class PostTile extends ConsumerWidget {
  const PostTile(this.post, {super.key, this.showTopBorder = true, this.large = false});

  final Post post;
  final bool showTopBorder;

  /// `.thread-root > .post > p` — the post a thread is about is set larger.
  final bool large;

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
            // `.posttop` — handle, time and the actions all on one line.
            Wrap(
              spacing: space4,
              runSpacing: space2,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                GestureDetector(
                  onTap: () => context.push('/u/${post.author.handle}'),
                  child: Text(
                    '@${post.author.handle}',
                    style: meta.asLink(palette).copyWith(color: palette.ink),
                  ),
                ),
                Text(
                  relativeTime(post.createdAt) +
                      (post.replyCount > 0
                          ? ' · ${post.replyCount} ${post.replyCount == 1 ? 'reply' : 'replies'}'
                          : ''),
                  style: meta.asLink(palette),
                ),
                ...postActions(context, ref, post, style: meta),
              ],
            ),
            const SizedBox(height: space3),
            PostBody(
              post.body,
              style: large
                  ? Theme.of(context).textTheme.bodyMedium!.copyWith(
                      fontSize: math.min(20.0, math.max(16.0, MediaQuery.sizeOf(context).width * 0.025)),
                      height: 1.55,
                      letterSpacing: -0.5,
                    )
                  : null,
            ),
            if (post.parentId case final parentId?) ParentQuote(parentId),
          ],
        ),
      ),
    );
  }
}
