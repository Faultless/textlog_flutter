import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locks.dart';
import '../../core/models.dart';
import '../router.dart';
import '../theme.dart';
import 'parent_quote.dart';
import 'link_preview_view.dart';
import 'post_body.dart';
import 'poll_view.dart';
import 'post_actions.dart';
import 'swipe_to_reply.dart';
import 'translatable_body.dart';
import 'post_meta.dart';
import 'todo_view.dart';

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
    this.lockedAbove = false,
  });

  final Post post;
  final bool showTopBorder;

  /// `.thread-root > .post > p` — the post a thread is about is set larger.
  final bool large;

  /// True when this page is about this post. It is the only case where deleting has
  /// to navigate somewhere — and the one case where opening it would mean opening
  /// the page you are already reading.
  final bool isSubject;

  /// Off inside a thread, where the parent is the post above.
  final bool showParent;

  /// Set by a thread whose root already locked it: an ancestor's `#lock` closes
  /// everything under it, and only the tree knows what is above this post.
  final bool lockedAbove;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final meta = Theme.of(context).textTheme.bodySmall!;

    return SwipeToReply(
      post: post,
      lockedAbove: lockedAbove,
      child: InkWell(
        // Nothing to open when this page is already about this post. It used to push
        // the route it was already on, so a tap anywhere on the card — including on a
        // checklist item somebody else's list would not let you tick — stacked another
        // copy of the same page, over and over.
        onTap: isSubject ? null : () => openPost(context, post.id),
        child: Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(
            horizontal: gutterOf(context),
            vertical: space5,
          ),
          decoration: BoxDecoration(
            border: Border(
              top: showTopBorder
                  ? BorderSide(color: palette.soft)
                  : BorderSide.none,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              PostContextLine(
                post: post,
                style: meta,
                onTap: () => openPost(context, post.id),
              ),
              const SizedBox(height: space3),
              TranslatableBody(
                post,
                style: large
                    ? Theme.of(context).textTheme.bodyMedium!.copyWith(
                        fontSize: math.min(
                          20.0,
                          math.max(
                            16.0,
                            MediaQuery.sizeOf(context).width * 0.025,
                          ),
                        ),
                        height: 1.55,
                        letterSpacing: -0.5,
                      )
                    : null,
              ),
              ExecutionOutput(post),
              PollView(post),
              TodoView(post),
              LocationPreview(post),
              LinkPreviews(post),
              if (showParent)
                if (post.parentId case final int parentId)
                  ParentQuote(parentId: parentId, parent: post.parent),
              const SizedBox(height: space3),
              // `.postfoot`
              Row(
                children: postActions(
                  context,
                  ref,
                  post,
                  style: meta,
                  isSubject: isSubject,
                  locked: threadLocked(post, inherited: lockedAbove),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
