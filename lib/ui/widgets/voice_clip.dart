import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

import '../../state/audio.dart';
import '../theme.dart';

/// A voice clip, played where it was linked.
///
/// The site plays a Vocaroo link inline from its own `/media/vocaroo/{id}` proxy, and
/// this does the same rather than handing the reader to Vocaroo — the proxy is a plain
/// ranged mp3, and going through it means listening tells Vocaroo nothing.
///
/// One line, because that is what a voice clip in a text feed deserves: a control, the
/// time, and a bar that fills. No artwork, no title, nothing to bury the post that
/// linked it.
class VoiceClip extends ConsumerWidget {
  const VoiceClip({super.key, required this.url, required this.streamUrl});

  /// The link as written, which identifies this clip among any others on the page.
  final String url;

  /// Where the audio actually comes from.
  final String streamUrl;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    // Watching only *which* clip is loaded. Nothing here reaches for the player
    // itself, so a card that is never pressed never needs an audio engine — which
    // is also what lets a widget test render one without a platform channel.
    final mine = ref.watch(playingClipProvider) == url;

    return Padding(
      padding: const EdgeInsets.only(top: space3),
      child: Container(
        decoration: BoxDecoration(
          color: palette.tagBg,
          border: Border.all(color: mine ? palette.accent : palette.soft),
        ),
        child: mine
            ? _Loaded(
                url: url,
                streamUrl: streamUrl,
                palette: palette,
                theme: theme,
              )
            : _Idle(
                url: url,
                streamUrl: streamUrl,
                palette: palette,
                theme: theme,
              ),
      ),
    );
  }
}

/// Not the clip that owns the player: a single press to make it so.
class _Idle extends ConsumerWidget {
  const _Idle({
    required this.url,
    required this.streamUrl,
    required this.palette,
    required this.theme,
  });

  final String url;
  final String streamUrl;
  final Palette palette;
  final TextTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) => _Row(
    label: 'voice clip',
    playing: false,
    palette: palette,
    theme: theme,
    onTap: () =>
        ref.read(playingClipProvider.notifier).toggle(url, streamUrl: streamUrl),
  );
}

/// The clip the player is loaded with, so it can show progress.
class _Loaded extends ConsumerWidget {
  const _Loaded({
    required this.url,
    required this.streamUrl,
    required this.palette,
    required this.theme,
  });

  final String url;
  final String streamUrl;
  final Palette palette;
  final TextTheme theme;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final player = ref.watch(audioPlayerProvider);

    return StreamBuilder<PlayerState>(
      stream: player.playerStateStream,
      builder: (context, stateSnapshot) {
        final playing = stateSnapshot.data?.playing ?? false;
        final loading = switch (stateSnapshot.data?.processingState) {
          ProcessingState.loading || ProcessingState.buffering => true,
          _ => false,
        };

        return StreamBuilder<Duration>(
          stream: player.positionStream,
          builder: (context, positionSnapshot) {
            final position = positionSnapshot.data ?? Duration.zero;
            final total = player.duration;
            return _Row(
              label: loading ? 'loading…' : _clock(position, total),
              playing: playing,
              // Only once a duration is known: a bar that jumps to full because the
              // total was zero for a frame reads as a bug.
              progress: total == null || total == Duration.zero
                  ? null
                  : (position.inMilliseconds / total.inMilliseconds).clamp(0.0, 1.0),
              palette: palette,
              theme: theme,
              onTap: () => ref
                  .read(playingClipProvider.notifier)
                  .toggle(url, streamUrl: streamUrl),
            );
          },
        );
      },
    );
  }

  /// `0:07 / 0:42`, or just the elapsed time until the total is known.
  static String _clock(Duration position, Duration? total) {
    String render(Duration d) =>
        '${d.inMinutes}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return total == null ? render(position) : '${render(position)} / ${render(total)}';
  }
}

class _Row extends StatelessWidget {
  const _Row({
    required this.label,
    required this.playing,
    required this.palette,
    required this.theme,
    required this.onTap,
    this.progress,
  });

  final String label;
  final bool playing;
  final Palette palette;
  final TextTheme theme;
  final VoidCallback onTap;
  final double? progress;

  @override
  Widget build(BuildContext context) => Semantics(
    button: true,
    label: playing ? 'pause the voice clip' : 'play the voice clip',
    child: GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Stack(
        children: [
          if (progress != null)
            Positioned.fill(
              child: FractionallySizedBox(
                alignment: Alignment.centerLeft,
                widthFactor: progress!,
                child: ColoredBox(color: palette.quoteBg),
              ),
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space3),
            child: Row(
              children: [
                // Characters rather than icons, which is what the rest of this app
                // does and what barebones mode would demand of it anyway.
                Text(
                  playing ? '❚❚' : '▶',
                  style: theme.bodySmall!.copyWith(color: palette.accent),
                ),
                const SizedBox(width: space3),
                Expanded(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.labelSmall!.copyWith(color: palette.muted),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    ),
  );
}
