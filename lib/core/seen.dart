/// When an unread row counts as read.
///
/// Marking on tap was the only rule, which meant scrolling through everything
/// addressed to you left it all still unread — the dots stayed until you pressed
/// "mark all as read", which is a chore the reader has already done by reading.
///
/// Pure so the rule can be argued with in a test rather than on a device: the widget
/// measures, this decides.
library;

import 'dart:ui' show Rect;

/// The rows fully inside [viewport], and therefore read.
///
/// *Fully* is the whole point. Half a row showing at the bottom edge is a row you
/// have not read, and marking it would quietly lose the thing you were scrolling
/// towards. Both edges have to be inside, so a row taller than the viewport is never
/// counted at all — the reader can still tap it, and a wall of text should not be
/// declared read because it happened to pass by.
Iterable<String> seenRows(Map<String, Rect> rows, Rect viewport) => [
  for (final MapEntry(key: id, value: box) in rows.entries)
    if (box.top >= viewport.top && box.bottom <= viewport.bottom) id,
];
