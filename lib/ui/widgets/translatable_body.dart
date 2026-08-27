import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../state/settings.dart';
import '../../state/translation.dart';
import '../theme.dart';
import 'post_body.dart';
import 'pressable.dart';

/// A post body, with a way to read it in English when it was not written in it.
///
/// The translation is the server's. It detects the language and translates once per
/// post, storing nothing when the body is already English — so the app neither
/// detects anything nor sends anybody's post to a third-party translator. All this
/// widget decides is whether to offer the swap.
class TranslatableBody extends ConsumerWidget {
  const TranslatableBody(this.post, {super.key, this.style, this.quiet = false});

  final Post post;
  final TextStyle? style;

  /// A quoted parent: same content, less contrast.
  final bool quiet;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final offer = ref.watch(settingsProvider).valueOrNull?.translate ?? true;
    // Nothing to offer unless the server stored a translation that actually differs
    // from the body. It sometimes hands back the input unchanged, and a button that
    // swaps a body for itself is worse than no button at all.
    if (!offer || !post.isTranslatable) {
      return PostBody(post.body, style: style, quiet: quiet);
    }

    final translated = ref.watch(translatedPostsProvider).contains(post.id);
    final palette = context.palette;
    final label = Theme.of(context).textTheme.labelSmall!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PostBody(
          translated ? post.translation! : post.body,
          // Keyed on which text is showing, so the body's own state — a revealed
          // spoiler, a revealed redaction — is not carried across a swap into
          // different words where it would make no sense.
          key: ValueKey(translated),
          style: style,
          quiet: quiet,
        ),
        const SizedBox(height: space2),
        Pressable(
          onTap: () => ref.read(translatedPostsProvider.notifier).toggle(post.id),
          builder: (context, pressed) => Text(
            translated ? 'show original' : 'translate',
            style: label.asLink(palette).copyWith(
              color: pressed ? palette.accent : palette.muted,
            ),
          ),
        ),
      ],
    );
  }
}
