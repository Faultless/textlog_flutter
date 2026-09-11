import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/body_tokens.dart';
import '../../core/models.dart';
import '../../core/post_context.dart';
import '../../state/session.dart';
import '../../state/settings.dart';
import '../theme.dart';
import 'pressable.dart';

/// `@handle`, in its own colour when it is yours, and `you` when the site would say
/// `you` — which it does for your own posts, so a thread reads as a conversation.
class HandleLink extends ConsumerWidget {
  const HandleLink(
    this.handle, {
    super.key,
    this.style,
    this.colour,
    this.asYou = false,
    this.hitPadding,
    this.ellipsize = false,
  });

  final String handle;
  final TextStyle? style;

  /// What to use when the handle is somebody else's.
  final Color? colour;

  /// Render your own handle as `you`, unlinked, the way the site does.
  final bool asYou;

  /// Overrides [Pressable]'s default hit box. The meta line trims the side the
  /// punctuation sits on, so `@bob:` does not render as `@bob :`.
  final EdgeInsets? hitPadding;

  /// Abbreviate rather than wrap when there is not room for the whole handle.
  final bool ellipsize;

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
      hitPadding: hitPadding ?? const EdgeInsets.symmetric(horizontal: space1, vertical: space2),
      onTap: () => context.push('/u/$handle'),
      builder: (context, pressed) => Text(
        '@$handle',
        maxLines: ellipsize ? 1 : null,
        overflow: ellipsize ? TextOverflow.ellipsis : null,
        softWrap: !ellipsize,
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
/// Both halves are the reader's to turn off. The stamp doubles as the way into a
/// post, so losing it costs something — but a reader who does not want to know how
/// old a post is, or how many replies it drew, should not have to, and the card
/// itself still opens the post either way.
class PostMeta extends ConsumerWidget {
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
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final base = style ?? Theme.of(context).textTheme.bodySmall!;
    final settings = ref.watch(settingsProvider).valueOrNull ?? const Settings();
    final showTime = settings.timestamps;
    final replies = settings.replyCounts ? replyCount : 0;
    // Nothing left to draw, and an empty tap target in a meta line reads as a bug.
    if (!showTime && replies == 0) return const SizedBox.shrink();

    return Pressable(
      onTap: onTap,
      builder: (context, pressed) {
        final link = base.asLink(palette).copyWith(color: pressed ? palette.accentDark : null);
        return Text.rich(
          // One line, abbreviated rather than wrapped: on a crowded row this is the
          // last part to give way, and when it does it must not take a second line
          // — or push the controls beside it off the edge.
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          TextSpan(
            children: [
              if (showTime) TextSpan(text: relativeTime(createdAt), style: link),
              if (replies > 0) ...[
                if (showTime)
                  TextSpan(
                    text: ' · ',
                    style: base.copyWith(color: palette.muted),
                  ),
                TextSpan(
                  text: '$replies ${replies == 1 ? 'reply' : 'replies'}',
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

/// Every text part of a single-line meta row abbreviates rather than overflowing.
/// Without this the parts that carry no handle — the label and its punctuation —
/// kept their full width and pushed the controls off the end of a narrow row.
const _clip = TextOverflow.ellipsis;

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
    this.singleLine = false,
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

  /// Keep the whole line on one row, abbreviating a handle that will not fit.
  ///
  /// On for anything with a control on the line — a fold toggle, a `top` link. Those
  /// are the header of an accordion, and a header that reflows drops its own control
  /// onto a second row and reads as broken.
  final bool singleLine;

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

    // A handle can be twenty-four characters, so on a single-line row it is the
    // part that gives way: wrapped in Flexible with an ellipsis, while the stamp
    // and any control keep their full width.
    final author = HandleLink(
      post.author.handle,
      style: base,
      colour: quoted ? palette.quoteInk : null,
      asYou: true,
      // No left padding: the first chip has to line up with the body below it.
      hitPadding: const EdgeInsets.only(right: space1, top: space2, bottom: space2),
      ellipsize: singleLine,
    );

    final label = switch (relation) {
      PostContext(hasLabel: false) => null,
      PostContext(target: final target?) => (
        Text(relation.label!, style: quiet, maxLines: 1, overflow: _clip),
        // The punctuation has to hug the handle, or the line reads "@bob :".
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(
              child: HandleLink(
                target.handle,
                style: base,
                colour: quoted ? palette.quoteInk : null,
                asYou: true,
                // The punctuation follows immediately, so nothing on the right.
                hitPadding: const EdgeInsets.only(left: space1, top: space2, bottom: space2),
                ellipsize: singleLine,
              ),
            ),
            // Flexible too: the tail is ` and mentioned you:` on a reply that did,
            // which is wider than the handle it follows. Fixed, it was the part that
            // pushed a crowded row over the edge.
            Flexible(child: Text(_tail(relation), style: quiet, maxLines: 1, overflow: _clip)),
          ],
        ),
      ),
      _ => (
        Text('${relation.label!}${_tail(relation)}', style: quiet, maxLines: 1, overflow: _clip),
        null,
      ),
    };

    final meta = PostMeta(
      createdAt: post.createdAt,
      replyCount: showReplyCount ? post.replyCount : 0,
      style: base,
      onTap: onTap,
    );

    if (!singleLine) {
      return Wrap(
        // Each tappable chip brings its own padding now, so the gaps come from that.
        spacing: space1,
        runSpacing: 0,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (showAuthor) author,
          if (label case (final word, final target?)) ...[word, target],
          if (label case (final word, null)) word,
          meta,
          ...trailing,
        ],
      );
    }

    return Row(
      children: [
        if (showAuthor) Flexible(child: author),
        if (label case (final word, final target?)) ...[
          Flexible(child: word),
          Flexible(child: target),
        ],
        if (label case (final word, null)) Flexible(child: word),
        // The handles give way first — a loose Flexible takes its natural width
        // while there is room, so the stamp only shortens once they have nothing
        // left to give. The controls keep their room throughout: they are fixed
        // boxes, and a control that is clipped is a control nobody can press.
        Flexible(child: meta),
        ...trailing,
      ],
    );
  }
}
