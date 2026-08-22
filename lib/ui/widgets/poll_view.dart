import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/models.dart';
import '../../core/polls.dart';
import '../theme.dart';

/// `.poll` — the options of a poll, read-only.
///
/// A poll lives in the post body (a line ending `#poll`, then the options), so the
/// app can always *show* one. Counting and casting a vote are a different matter:
/// there is no poll endpoint in the public API — the site votes by form POST — so
/// tapping an option opens the post on textlog.cc rather than pretending.
///
/// Showing it anyway is not optional. Without this the option lines render as
/// ordinary body text, which is simply not what the author wrote.
class PollView extends ConsumerWidget {
  const PollView(this.post, {super.key});

  final Post post;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final poll = parsePoll(post.body);
    if (poll == null) return const SizedBox.shrink();

    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final closed = pollClosed(post.createdAt);

    return Padding(
      padding: const EdgeInsets.only(top: space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final option in poll.options)
            Padding(
              padding: const EdgeInsets.only(bottom: space2),
              child: _Option(option, closed: closed, url: post.url),
            ),
          Text(
            closed ? 'this poll has closed' : 'vote on textlog.cc',
            style: theme.labelSmall!.copyWith(color: palette.muted),
          ),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option(this.label, {required this.closed, required this.url});

  final String label;
  final bool closed;
  final Uri url;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Semantics(
      button: !closed,
      label: closed ? 'poll option $label' : 'vote for $label on textlog.cc',
      child: GestureDetector(
        onTap: closed ? null : () => launchUrl(url, mode: LaunchMode.externalApplication),
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space3),
          decoration: BoxDecoration(
            color: palette.tagBg,
            border: Border.all(color: closed ? palette.soft : palette.linkBorder),
          ),
          child: Text(
            label,
            style: theme.bodySmall!.copyWith(
              color: closed ? palette.muted : palette.ink,
            ),
          ),
        ),
      ),
    );
  }
}
