import 'package:flutter/material.dart';

import '../theme.dart';

/// An icon, or the character textlog would have used.
///
/// The site is text: its controls are `+`, `−`, `/` and words. Barebones mode takes
/// the app back to that, so every icon in the app goes through here and there is one
/// place that decides which of the two you get.
class Glyph extends StatelessWidget {
  const Glyph(this.icon, this.plain, {super.key, this.size = 16, this.colour});

  final IconData icon;

  /// What to draw instead, in barebones mode.
  final String plain;

  final double size;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    final ink = colour ?? context.palette.muted;
    if (!context.chrome.plain) return Icon(icon, size: size, color: ink);

    return Text(
      plain,
      textAlign: TextAlign.center,
      style: Theme.of(context).textTheme.bodySmall!.copyWith(
        color: ink,
        height: 1,
        // Held at the icon's own size so swapping one for the other does not move
        // anything around it.
        fontSize: size,
      ),
    );
  }
}

/// The glyphs the app uses, named rather than spelled out at each call site.
abstract final class Glyphs {
  static const back = ('<', Icons.arrow_back);
  static const search = ('/', Icons.search);
  static const appearance = ('=', Icons.tune);
  static const write = ('+', Icons.edit);
  static const more = ('…', Icons.more_horiz);
  static const close = ('x', Icons.close);
}

/// `[x]` / `[ ]` instead of a Material switch.
class PlainCheck extends StatelessWidget {
  const PlainCheck({super.key, required this.value, required this.onChanged});

  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme.bodyMedium!;

    if (!context.chrome.plain) {
      return Switch(
        value: value,
        onChanged: onChanged,
        activeThumbColor: palette.bg,
        activeTrackColor: palette.accent,
        inactiveThumbColor: palette.muted,
        inactiveTrackColor: palette.bg,
        trackOutlineColor: WidgetStatePropertyAll(palette.soft),
      );
    }

    return Semantics(
      // Only one of checked/toggled may be set, and `[x]` reads as a checkbox.
      checked: value,
      child: GestureDetector(
        onTap: () => onChanged(!value),
        behavior: HitTestBehavior.opaque,
        child: Padding(
          // A `[x]` is three characters wide; the padding is what makes it tappable.
          padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
          child: Text(
            value ? '[x]' : '[ ]',
            style: theme.copyWith(color: value ? palette.accent : palette.muted),
          ),
        ),
      ),
    );
  }
}
