import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/body_tokens.dart';
import '../../core/models.dart';
import '../../core/post_context.dart';
import '../../state/session.dart';
import '../theme.dart';
import 'pressable.dart';

/// `@handle`, in its own colour when it is yours, and `you` when the site would say
/// `you` — which it does for your own posts, so a thread reads as a conversation.
class HandleLink extends ConsumerWidget {
  const HandleLink(this.handle, {super.key, this.style, this.colour, this.asYou = false});

  final String handle;
  final TextStyle? style;

  /// What to use when the handle is somebody else's.
  final Color? colour;

  /// Render your own handle as `you`, unlinked, the way the site does.
  final bool asYou;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final base = style ?? Theme.of(context).textTheme.bodySmall!;
    final mine = ref.watch(viewerHandleProvider) == handle;

    // A removed account is not a link to anywhere.
    if (isDeletedHandle(handle)) {
      return Text('(deleted account)', style: base.copyWith(color: palette.muted));
    }
    if (mine && asYou) {
      return Text('you', style: base.copyWith(color: palette.selfInk));
    }

    final ink = mine ? palette.selfInk : (colour ?? palette.ink);
    return Pressable(
      onTap: () => context.push('/u/$handle'),
      builder: (context, pressed) => Text(
        '@$handle',
        style: base.asLink(palette).copyWith(color: pressed ? palette.accent : ink),
      ),
    );
  }
}

/// `13h · 2 replies`. Each part carries its own underline; the separator carries
/// none, so the rule does not run across the gap between them.
///
/// The site labels this `read` and drops the time entirely. On a phone that throws
/// away the one thing a dense feed most needs, so the app keeps the stamp *as* the
/// affordance: same tap target, same place, more information.
class PostMeta extends StatelessWidget {
  const PostMeta({
    super.key,
    required this.createdAt,
    required this.replyCount,
    this.style,
    this.onTap,
  });

  final DateTime createdAt;
  final int replyCount;
  final TextStyle? style;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final base = style ?? Theme.of(context).textTheme.bodySmall!;

    return Pressable(
      onTap: onTap,
      builder: (context, pressed) {
        final link = base.asLink(palette).copyWith(color: pressed ? palette.accentDark : null);
        return Text.rich(
          TextSpan(
            children: [
              TextSpan(text: relativeTime(createdAt), style: link),
              if (replyCount > 0) ...[
                TextSpan(
                  text: ' · ',
                  style: base.copyWith(color: palette.muted),
                ),
                TextSpan(
                  text: '$replyCount ${replyCount == 1 ? 'reply' : 'replies'}',
                  style: link,
                ),
              ],
            ],
          ),
        );
      },
    );
  }
}

/// `and mentioned you:` or plain `:`, as the server appends it.
String _tail(PostContext relation) => relation.mentionedYou ? ' and mentioned you:' : ':';

/// `.posttop` — `@alice replied to @bob:` and the stamp, on one line.
///
/// Everything it needs is on the post already: the server inlines the quoted parent,
/// so naming who was replied to costs nothing.
class PostContextLine extends ConsumerWidget {
  const PostContextLine({
    super.key,
    required this.post,
    this.style,
    this.onTap,
    this.showAuthor = true,
    this.quoted = false,
    this.showReplyCount = true,
    this.context$,
    this.trailing = const [],
  });

  final Post post;
  final TextStyle? style;
  final VoidCallback? onTap;

  /// Off inside a reply tree, where the branch already says who is speaking… except
  /// it does not, so this stays on almost everywhere.
  final bool showAuthor;

  /// A quieter palette, for a quoted parent.
  final bool quoted;

  /// Off inside a reply tree, where the replies are drawn below the post and a
  /// count next to them says nothing the reader cannot see.
  final bool showReplyCount;

  /// Precomputed relation, when the caller has a better idea than the post alone —
  /// a quote that found its grandparent in the cache, for instance.
  final PostContext? context$;

  /// The fold control, `top`, and anything else that belongs on this line.
  final List<Widget> trailing;

  @override
  Widget build(BuildContext buildContext, WidgetRef ref) {
    final palette = buildContext.palette;
    final base = style ?? Theme.of(buildContext).textTheme.bodySmall!;
    final quiet = base.copyWith(color: quoted ? palette.quoteInk : palette.muted);
    final viewer = ref.watch(viewerHandleProvider);
    final relation = context$ ?? postContextOf(post, viewerHandle: viewer);

    return Wrap(
      spacing: space2,
      runSpacing: space1,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (showAuthor)
          HandleLink(
            post.author.handle,
            style: base,
            colour: quoted ? palette.quoteInk : null,
            asYou: true,
          ),
        if (relation.hasLabel)
          if (relation.target case final target?) ...[
            Text(relation.label!, style: quiet),
            // The punctuation has to hug the handle, or the line reads "@bob :".
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                HandleLink(
                  target.handle,
                  style: base,
                  colour: quoted ? palette.quoteInk : null,
                  asYou: true,
                ),
                Text(_tail(relation), style: quiet),
              ],
            ),
          ] else
            Text('${relation.label!}${_tail(relation)}', style: quiet),
        PostMeta(
          createdAt: post.createdAt,
          replyCount: showReplyCount ? post.replyCount : 0,
          style: base,
          onTap: onTap,
        ),
        ...trailing,
      ],
    );
  }
}
