import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/providers.dart';
import '../theme.dart';
import 'post_body.dart';
import 'post_meta.dart';

/// `.parent-quote` — the post being replied to, quoted beneath the reply.
///
/// The feed endpoints return `parent_id` but not the parent itself, so each quote
/// is a second request. Riverpod caches by id, so a thread where several replies
/// share a parent fetches it once, and only tiles actually built ask for one.
class ParentQuote extends ConsumerWidget {
  const ParentQuote(this.parentId, {super.key});

  final int parentId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final parent = ref.watch(postProvider(parentId));
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    // A quote is decoration. While it loads, or if the parent was deleted, show
    // nothing rather than a spinner or an error in the middle of the feed.
    if (parent case AsyncData(:final value)) {
      return GestureDetector(
        onTap: () => context.push('/post/$parentId'),
        child: Container(
          margin: EdgeInsets.only(top: space2, left: quoteIndentOf(context)),
          padding: const EdgeInsets.all(space3),
          color: palette.quoteBg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Flexible(
                    child: HandleLink(
                      value.author.handle,
                      style: theme.labelSmall!,
                      colour: palette.quoteInk,
                    ),
                  ),
                  const SizedBox(width: space3),
                  PostMeta(
                    createdAt: value.createdAt,
                    replyCount: value.replyCount,
                    style: theme.labelSmall!,
                    onTap: () => context.push('/post/$parentId'),
                  ),
                ],
              ),
              const SizedBox(height: space2),
              PostBody(
                value.body,
                style: theme.bodySmall!.copyWith(color: palette.quoteInk, height: 1.55),
              ),
            ],
          ),
        ),
      );
    }
    return const SizedBox.shrink();
  }
}
