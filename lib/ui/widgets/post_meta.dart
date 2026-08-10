import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/body_tokens.dart';
import '../../state/session.dart';
import '../theme.dart';
import 'pressable.dart';

/// `@handle`, in its own colour when it is yours.
class HandleLink extends ConsumerWidget {
  const HandleLink(this.handle, {super.key, this.style, this.colour});

  final String handle;
  final TextStyle? style;

  /// What to use when the handle is somebody else's.
  final Color? colour;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final base = style ?? Theme.of(context).textTheme.bodySmall!;
    final mine = ref.watch(viewerHandleProvider) == handle;
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
