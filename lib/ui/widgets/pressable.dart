import 'package:flutter/material.dart';

/// A tap target that says it is being pressed.
///
/// The whole app is text you can tap, so a tap used to be invisible until whatever
/// it did appeared. [builder] gets `pressed` and decides what that looks like.
class Pressable extends StatefulWidget {
  const Pressable({
    super.key,
    required this.builder,
    this.onTap,
    this.semanticLabel,
  });

  final Widget Function(BuildContext context, bool pressed) builder;
  final VoidCallback? onTap;
  final String? semanticLabel;

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
        child: widget.builder(context, _pressed && enabled),
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
