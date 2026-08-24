import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:just_audio/just_audio.dart';

/// One player for the whole app.
///
/// Two clips playing over each other is never what anyone wanted, and a player per
/// card would hold a decoder open for every card that scrolled past. So there is one,
/// and [playingClipProvider] says which clip currently owns it.
///
/// Created lazily on first play. That matters beyond tidiness: a widget test that
/// renders a post with a clip in it must not need a platform channel, and it does not
/// — nothing touches this until someone presses play.
final audioPlayerProvider = Provider<AudioPlayer>((ref) {
  final player = AudioPlayer();
  ref.onDispose(player.dispose);
  return player;
});

/// The clip the player is loaded with, or null when it is idle.
///
/// Held apart from the player so a card can draw itself — play or pause — without
/// reaching for an audio engine it may never need.
final playingClipProvider = NotifierProvider<PlayingClip, String?>(PlayingClip.new);

class PlayingClip extends Notifier<String?> {
  @override
  String? build() => null;

  /// Play the clip linked as [url], streaming from [streamUrl], and stop whatever
  /// else was playing. Pressing the clip that is already playing pauses it, which is
  /// what a single play/pause control means.
  ///
  /// Two URLs, deliberately: the link is what identifies this clip among the others
  /// on the page, and the stream is where the bytes come from. Handing the link to
  /// the player instead — which is what this did at first — asks it to decode
  /// Vocaroo's *web page*, and the failure reads as an unplayable clip rather than
  /// the mix-up it is.
  Future<void> toggle(String url, {required String streamUrl}) async {
    final player = ref.read(audioPlayerProvider);
    if (state == url) {
      if (player.playing) {
        await player.pause();
      } else {
        // Restart rather than resume from the end: a finished clip pressed again
        // should play, not sit at its own last frame doing nothing.
        if (player.position >= (player.duration ?? Duration.zero)) {
          await player.seek(Duration.zero);
        }
        await player.play();
      }
      // Nudge listeners: `playing` is not part of this notifier's state, so a
      // pause has nothing else to tell them by.
      ref.notifyListeners();
      return;
    }

    // Claimed before loading, so the control can say it is working on it rather
    // than looking untouched while the first bytes arrive.
    state = url;
    try {
      await player.setUrl(streamUrl);
      await player.play();
    } catch (_) {
      // A clip that will not load is not worth a dialog over a text feed. Drop back
      // to idle so the control offers to try again.
      if (state == url) state = null;
    }
  }
}
