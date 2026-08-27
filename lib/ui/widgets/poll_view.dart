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
import 'post_body.dart';

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
    final session = ref.read(viewerProvider);
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
          // Still withheld: the server decides when to say which one was right, and
          // guessing here would give the answer away a round trip early.
          correct: option.correct,
        ),
    ],
    totalVotes: poll.totalVotes == null ? null : poll.totalVotes! + 1,
    expired: poll.expired,
    expiresAt: poll.expiresAt,
    viewerVoted: true,
    kind: poll.kind,
    explanation: poll.explanation,
  );

  @override
  Widget build(BuildContext context) {
    final poll = _poll;
    if (poll == null) return const SizedBox.shrink();

    final session = ref.watch(viewerProvider);
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
                // Marking the right answer only once the server has told us, which
                // it does the moment you answer.
                correct: option.correct,
              ),
            ),
          if (poll.explanation case final explanation?) ...[
            const SizedBox(height: space1),
            _Explanation(explanation),
          ],
          _Footing(poll, signedIn: session != null),
        ],
      ),
    );
  }
}

class _Option extends StatelessWidget {
  const _Option(
    this.option, {
    required this.share,
    required this.onTap,
    required this.busy,
    this.correct,
  });

  final PollOption option;

  /// A quiz, answered: true on the right one, false on the rest, null while the
  /// server is still withholding it — and always null on an ordinary poll.
  final bool? correct;

  /// Null while the tally is withheld — then this is a button, not a result.
  final double? share;

  final VoidCallback? onTap;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final percent = share == null ? null : (share! * 100).round();

    // Green for the answer, red for the one you picked instead. Nothing is coloured
    // until the server reveals it, so a quiz reads exactly like a poll until then.
    final verdict = switch (correct) {
      true => palette.accent,
      false when option.selected => palette.errorInk,
      _ => null,
    };

    return Semantics(
      button: onTap != null,
      selected: option.selected,
      label: switch ((percent, correct)) {
        (null, _) => 'vote for ${option.label}',
        (final percent?, true) => '${option.label}, the answer, $percent per cent',
        (final percent?, false) when option.selected =>
          '${option.label}, your answer, wrong, $percent per cent',
        (final percent?, _) => '${option.label}, $percent per cent',
      },
      child: GestureDetector(
        // Absorbed whether or not it can be voted on, for the same reason a checkbox
        // is: an option reads as a button, and pressing one should never do something
        // unrelated. The footing below says why it cannot be voted on.
        onTap: onTap ?? () {},
        behavior: HitTestBehavior.opaque,
        child: Container(
          width: double.infinity,
          decoration: BoxDecoration(
            color: palette.tagBg,
            border: Border.all(
              color: verdict ??
                  (option.selected
                      ? palette.accent
                      : (onTap != null ? palette.linkBorder : palette.soft)),
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
                    else ...[
                      // A tick or a cross rather than colour alone, which says
                      // nothing to a reader who cannot tell these two apart.
                      if (correct == true || (correct == false && option.selected))
                        Padding(
                          padding: const EdgeInsets.only(right: space2),
                          child: Text(
                            correct == true ? '✓' : '✗',
                            style: theme.bodySmall!.copyWith(color: verdict),
                          ),
                        ),
                      if (percent != null)
                        Text(
                          '$percent%',
                          style: theme.bodySmall!.copyWith(color: palette.quoteInk),
                        ),
                    ],
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
      final answers = '$total ${total == 1 ? 'answer' : 'answers'}';
      final votes = '$total ${total == 1 ? 'vote' : 'votes'}';
      return Text(
        poll.isQuiz
            // No "closed": a quiz has no deadline to have passed.
            ? '$answers${switch (poll.gotItRight) {
                true => ' · you got it',
                false => ' · not this time',
                null => '',
              }}'
            : '$votes${poll.expired ? ' · closed' : ''}',
        style: style,
      );
    }
    if (!signedIn) {
      // The app's own sign-in, not the post in a browser — which is what this used to
      // open, having just told the reader to sign in.
      return GestureDetector(
        onTap: () => context.push('/me'),
        behavior: HitTestBehavior.opaque,
        child: Text(
          poll.isQuiz ? 'sign in to answer' : 'sign in to vote',
          style: style.asLink(palette),
        ),
      );
    }
    return Text(
      poll.isQuiz ? 'the answer shows once you pick' : 'results show once you vote',
      style: style,
    );
  }
}

/// Why the answer is the answer. A quiz only, and the server withholds it until the
/// reader has committed to one — so its presence is what says they have.
class _Explanation extends StatelessWidget {
  const _Explanation(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: space2),
      padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
      decoration: BoxDecoration(
        color: palette.quoteBg,
        border: Border(left: BorderSide(color: palette.accent, width: 2)),
      ),
      // Through the body renderer: an explanation is written the same way a post is,
      // so it can carry a link or a mention and they should work.
      child: PostBody(text, style: Theme.of(context).textTheme.bodySmall, quiet: true),
    );
  }
}
