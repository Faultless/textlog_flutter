import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/post_context.dart';
import '../../state/cache.dart';
import '../../state/session.dart';
import '../theme.dart';
import '../screens/web_action.dart';
import 'compose_sheet.dart';
import 'poll_view.dart';
import 'post_body.dart';
import 'post_meta.dart';
import 'pressable.dart';
import 'todo_view.dart';

/// `.parent-quote` — the post being replied to, quoted beneath the reply.
///
/// This used to be a request per quote: feeds returned `parent_id` and nothing else,
/// so every reply on screen fetched its own parent. The server now inlines the whole
/// quoted post, so a feed of fifty replies costs one request instead of fifty-one.
///
/// A `parent_id` with no `parent` means the parent is gone; the site prints
/// `(deleted post)` and links to it, which is what happens here too.
class ParentQuote extends ConsumerWidget {
  const ParentQuote({super.key, required this.parentId, this.parent});

  final int parentId;
  final Post? parent;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final quote = parent ?? ref.watch(postCacheProvider)[parentId];

    if (quote == null) {
      return _Frame(
        onTap: () => context.push('/post/$parentId'),
        child: Text(
          '(deleted post)',
          style: theme.labelSmall!.asLink(palette).copyWith(color: palette.quoteInk),
        ),
      );
    }

    final viewer = ref.watch(viewerHandleProvider);
    final relation = quotedContextOf(
      quote,
      viewerHandle: viewer,
      // Free: the grandparent is very often a post that was just on screen. When it
      // is not, the quote simply says less rather than paying for a request.
      lookUp: (id) => ref.read(postCacheProvider)[id],
    );

    return _Frame(
      onTap: () => context.push('/post/$parentId'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PostContextLine(
            post: quote,
            style: theme.labelSmall!,
            quoted: true,
            // Keeps the `top` link on the same line as the handle it belongs to.
            singleLine: true,
            context$: relation,
            onTap: () => context.push('/post/$parentId'),
            trailing: [
              // Straight to the top of the conversation this quote sits in.
              if (quote.topId case final topId?)
                Pressable(
                  onTap: () => context.push('/post/$topId'),
                  builder: (context, pressed) => Text(
                    'top',
                    style: theme.labelSmall!.asLink(palette).copyWith(
                      color: pressed ? palette.accent : palette.quoteInk,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: space2),
          PostBody(
            quote.body,
            quiet: true,
            style: theme.bodySmall!.copyWith(color: palette.quoteInk, height: 1.55),
          ),
          // The site shows a quoted poll and checklist too — without them a quote of
          // a poll is a question with no options under it.
          PollView(quote),
          TodoView(quote),
          const SizedBox(height: space2),
          // `.parent-quote-foot` — reply to the quoted post, not to the reply.
          _QuoteReply(quote),
        ],
      ),
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
    onTap: onTap,
    child: Container(
      width: double.infinity,
      margin: EdgeInsets.only(top: space2, left: quoteIndentOf(context)),
      padding: const EdgeInsets.all(space3),
      color: context.palette.quoteBg,
      child: child,
    ),
  );
}

/// `continue` on your own post, `reply` on anyone else's — the wording the site uses.
class _QuoteReply extends ConsumerWidget {
  const _QuoteReply(this.post);

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider).valueOrNull;
    final mine = session != null && session.account.handle == post.author.handle;

    return Pressable(
      onTap: () async {
        if (session == null) {
          await openReply(ref, post.id);
          return;
        }
        await showCompose(context, kind: ComposeKind.reply, target: post);
      },
      builder: (context, pressed) => Text(
        session == null
            ? 'sign in to reply'
            : mine
            ? 'continue'
            : 'reply',
        style: theme.labelSmall!.asLink(palette).copyWith(
          color: pressed ? palette.accent : palette.quoteInk,
        ),
      ),
    );
  }
}
