import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../theme.dart';
import 'parent_quote.dart';
import 'poll_view.dart';
import 'post_actions.dart';
import 'post_body.dart';
import 'post_meta.dart';

/// `.post` — 24px/gutter padding, hairline top rule, the meta line in words above
/// the body, the quoted parent beneath it, and the reply action at the foot.
///
/// The reply link sits at the bottom because that is where the site moved it: with a
/// quoted parent in between, an action at the top acts on something you have not
/// read yet.
class PostTile extends ConsumerWidget {
  const PostTile(
    this.post, {
    super.key,
    this.showTopBorder = true,
    this.large = false,
    this.isSubject = false,
    this.showParent = true,
  });

  final Post post;
  final bool showTopBorder;

  /// `.thread-root > .post > p` — the post a thread is about is set larger.
  final bool large;

  /// True when this page is about this post, which is the only case where deleting
  /// it has to navigate somewhere.
  final bool isSubject;

  /// Off inside a thread, where the parent is the post above.
  final bool showParent;

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
            PostContextLine(
              post: post,
              style: meta,
              onTap: () => context.push('/post/${post.id}'),
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
            PollView(post),
            if (showParent)
              if (post.parentId case final int parentId)
                ParentQuote(parentId: parentId, parent: post.parent),
            const SizedBox(height: space3),
            // `.postfoot`
            Row(
              children: postActions(context, ref, post, style: meta, isSubject: isSubject),
            ),
          ],
        ),
      ),
    );
  }
}
