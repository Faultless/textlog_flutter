import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../state/cache.dart';
import '../../state/feed.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../theme.dart';
import 'post_actions.dart';

/// `.poll` — the options, the tally, and a way to vote.
///
/// This used to be read-only, parsed out of the body, because the API carried nothing
/// about polls. It carries all of it now: the options with their ids, the counts, and
/// whether you voted — and there is an endpoint to vote through, so a tap here casts
/// a real vote instead of opening a browser.
///
/// The tally is withheld by the *server* until the poll closes or you have voted, so
/// a count cannot sway your choice. That is why `votes` is nullable rather than zero.
class PollView extends ConsumerStatefulWidget {
  const PollView(this.post, {super.key});

  final Post post;

  @override
  ConsumerState<PollView> createState() => _PollViewState();
}

class _PollViewState extends ConsumerState<PollView> {
  /// Set the moment a vote is cast, so the bars appear without waiting on the answer.
  Poll? _optimistic;
  int? _pending;
  var _busy = false;

  Poll? get _poll => _optimistic ?? widget.post.poll;

  Future<void> _vote(PollOption option) async {
    final session = ref.read(sessionProvider).valueOrNull;
    final poll = _poll;
    if (session == null || poll == null || _busy || poll.viewerVoted || poll.expired) return;

    // Show the result immediately, with this option counted. The server is about to
    // reveal the tally anyway, and waiting for it makes the tap feel unregistered.
    setState(() {
      _busy = true;
      _pending = option.id;
      _optimistic = _withVote(poll, option);
    });

    try {
      final voted = await ref.read(apiProvider).votePoll(session.token, widget.post.id, option.id);
      if (!mounted) return;
      setState(() => _optimistic = voted.poll);
      // The post is the poll's home; every copy of it should agree.
      ref.read(postCacheProvider).replace(voted);
      applyToLiveFeeds(voted.id, voted);
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() => _optimistic = null);
      toast(context, failure.message);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  /// The tally as it will read once this vote lands, so the bars can be drawn now.
  Poll _withVote(Poll poll, PollOption chosen) => Poll(
    options: [
      for (final option in poll.options)
        PollOption(
          id: option.id,
          label: option.label,
          // Unknown until the server answers; a guess of zero would draw empty bars.
          votes: option.votes == null
              ? null
              : option.votes! + (option.id == chosen.id ? 1 : 0),
          selected: option.id == chosen.id,
        ),
    ],
    totalVotes: poll.totalVotes == null ? null : poll.totalVotes! + 1,
    expired: poll.expired,
    expiresAt: poll.expiresAt,
    viewerVoted: true,
  );

  @override
  Widget build(BuildContext context) {
    final poll = _poll;
    if (poll == null) return const SizedBox.shrink();

    final session = ref.watch(sessionProvider).valueOrNull;
    final canVote = session != null && poll.open && !poll.viewerVoted;

    return Padding(
      padding: const EdgeInsets.only(top: space3),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final option in poll.options)
            Padding(
              padding: const EdgeInsets.only(bottom: space2),
              child: _Option(
                option,
                share: poll.shareOf(option),
                onTap: canVote ? () => _vote(option) : null,
                busy: _busy && _pending == option.id,
              ),
            ),
          _Footing(poll, signedIn: session != null),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option(this.option, {required this.share, required this.onTap, required this.busy});

  final PollOption option;

  /// Null while the tally is withheld — then this is a button, not a result.
  final double? share;

  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final percent = share == null ? null : (share! * 100).round();

    return Semantics(
      button: onTap != null,
      selected: option.selected,
      label: percent == null
          ? 'vote for ${option.label}'
          : '${option.label}, $percent per cent',
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.tagBg,
            border: Border.all(
              color: option.selected
                  ? palette.accent
                  : (onTap != null ? palette.linkBorder : palette.soft),
            ),
          ),
          child: Stack(
            children: [
              // `.poll-result-fill` — the bar is behind the label rather than beside
              // it, so a long option is not squeezed by its own result.
              if (share != null)
                Positioned.fill(
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: share!.clamp(0.0, 1.0),
                    child: ColoredBox(
                      color: option.selected ? palette.quoteBg : palette.soft,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space3),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        option.label,
                        style: theme.bodySmall!.copyWith(
                          color: palette.ink,
                          fontWeight: option.selected ? FontWeight.w700 : null,
                          fontVariations: option.selected
                              ? const [FontVariation.weight(700)]
                              : null,
                        ),
                      ),
                    ),
                    if (busy)
                      Text('…', style: theme.bodySmall!.copyWith(color: palette.muted))
                    else if (percent != null)
                      Text(
                        '$percent%',
                        style: theme.bodySmall!.copyWith(color: palette.quoteInk),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// What is left to say: how many voted, or why you cannot.
class _Footing extends StatelessWidget {
  const _Footing(this.poll, {required this.signedIn});

  final Poll poll;
  final bool signedIn;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(context).textTheme.labelSmall!.copyWith(color: palette.muted);

    if (poll.revealed) {
      final total = poll.totalVotes ?? 0;
      return Text(
        '$total ${total == 1 ? 'vote' : 'votes'}'
        '${poll.expired ? ' · closed' : ''}',
        style: style,
      );
    }
    if (!signedIn) {
      // The app's own sign-in, not the post in a browser — which is what this used to
      // open, having just told the reader to sign in.
      return GestureDetector(
        onTap: () => context.push('/me'),
        behavior: HitTestBehavior.opaque,
        child: Text('sign in to vote', style: style.asLink(palette)),
      );
    }
    return Text('results show once you vote', style: style);
  }
}
