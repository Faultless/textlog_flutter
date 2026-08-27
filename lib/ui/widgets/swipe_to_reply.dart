import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/locks.dart';
import '../../core/models.dart';
import '../../state/session.dart';
import '../../state/settings.dart';
import '../theme.dart';
import 'compose_sheet.dart';
import '../screens/web_action.dart';

/// Drag a post sideways to reply to it.
///
/// The reply link is still there and still does the same thing; this is the shortcut
/// for the action you take most often, on the hand you are already holding the phone
/// with. It goes *leftwards* deliberately: a rightward drag from the left edge is the
/// system's back gesture on Android and iOS both, and competing with that would break
/// something people rely on to win something they do not yet know exists.
///
/// Nothing is destructive, so nothing needs confirming — the sheet opens, and closing
/// it without posting costs the reader a swipe.
class SwipeToReply extends ConsumerStatefulWidget {
  const SwipeToReply({
    super.key,
    required this.post,
    required this.child,
    this.lockedAbove = false,
  });

  final Post post;
  final Widget child;

  /// A `#lock` above this post. There is nothing to swipe towards on a thread that
  /// will refuse the reply.
  final bool lockedAbove;

  @override
  ConsumerState<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends ConsumerState<SwipeToReply> {
  /// How far the card has been dragged, in pixels, always negative or zero.
  var _offset = 0.0;

  /// Past this the reply opens on release. Far enough that a sloppy vertical scroll
  /// does not trip it, close enough to reach with a thumb.
  static const _trigger = 72.0;

  /// The card stops moving here, so the drag has a floor to push against rather than
  /// sliding the post off the screen.
  static const _limit = 96.0;

  bool get _armed => _offset.abs() >= _trigger;

  @override
  Widget build(BuildContext context) {
    final enabled = ref.watch(settingsProvider).valueOrNull?.swipeToReply ?? true;
    final locked = threadLocked(widget.post, inherited: widget.lockedAbove);
    if (!enabled || locked) return widget.child;

    final palette = context.palette;

    return GestureDetector(
      // Horizontal only. The vertical drag belongs to the list, and claiming both
      // would make a feed impossible to scroll.
      onHorizontalDragUpdate: (details) => setState(() {
        _offset = (_offset + details.delta.dx).clamp(-_limit, 0.0);
      }),
      onHorizontalDragEnd: (_) {
        final go = _armed;
        setState(() => _offset = 0);
        if (go) _reply();
      },
      onHorizontalDragCancel: () => setState(() => _offset = 0),
      child: Stack(
        children: [
          // The hint sits behind the card and is revealed by it moving, rather than
          // being animated in on top — so it can never cover the post it belongs to.
          Positioned.fill(
            child: Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: EdgeInsets.only(right: gutterOf(context)),
                child: Opacity(
                  opacity: (_offset.abs() / _trigger).clamp(0.0, 1.0),
                  child: Text(
                    'reply',
                    style: Theme.of(context).textTheme.labelSmall!.copyWith(
                      color: _armed ? palette.accent : palette.muted,
                    ),
                  ),
                ),
              ),
            ),
          ),
          Transform.translate(
            offset: Offset(_offset, 0),
            // Opaque so the post's own background travels with it and the hint is
            // uncovered rather than showing through.
            child: ColoredBox(color: palette.bg, child: widget.child),
          ),
        ],
      ),
    );
  }

  Future<void> _reply() async {
    final session = ref.read(viewerProvider);
    if (session == null) {
      // Same landing as the reply link: somewhere you can actually sign in, rather
      // than a compose box that cannot post.
      await openReply(ref, widget.post.id);
      return;
    }
    if (!mounted) return;
    await showCompose(context, kind: ComposeKind.reply, target: widget.post);
  }
}
