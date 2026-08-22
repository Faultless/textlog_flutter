import 'package:flutter/material.dart';

import '../theme.dart';

/// A tap target that says it is being pressed.
///
/// The whole app is text you can tap, so a tap used to be invisible until whatever
/// it did appeared. [builder] gets `pressed` and decides what that looks like.
///
/// It also carries the padding that makes those taps land. This app is deliberately
/// as dense as the website, and on the website a 12px link is fine because it is
/// being clicked with a mouse. Measured in a phone viewport, every link in the app
/// was a 16px-tall target — half the height a thumb needs. The padding here is what
/// closes that gap, and it is a default rather than a per-caller decision so a new
/// link cannot quietly reintroduce the problem.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.semanticLabel,
    this.hitPadding = const EdgeInsets.symmetric(horizontal: space1, vertical: space2),
  });

  final Widget Function(BuildContext context, bool pressed) builder;
  final VoidCallback? onTap;
  final String? semanticLabel;

  /// Grows the hit box around the text. Set it to zero where the caller has already
  /// provided room, so the padding is not paid twice.
  final EdgeInsets hitPadding;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  var _pressed = false;

  void _set(bool value) {
    if (_pressed != value && mounted) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;

    final child = GestureDetector(
      onTap: widget.onTap,
      onTapDown: enabled ? (_) => _set(true) : null,
      onTapUp: enabled ? (_) => _set(false) : null,
      onTapCancel: enabled ? () => _set(false) : null,
      behavior: HitTestBehavior.opaque,
      child: MouseRegion(
        cursor: enabled ? SystemMouseCursors.click : MouseCursor.defer,
        onExit: (_) => _set(false),
        child: Padding(
          padding: widget.hitPadding,
          child: widget.builder(context, _pressed && enabled),
        ),
      ),
    );

    if (widget.semanticLabel == null) return child;
    return Semantics(
      container: true,
      button: true,
      excludeSemantics: true,
      label: widget.semanticLabel,
      child: child,
    );
  }
}
