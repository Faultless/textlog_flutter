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

/// How much of a row has to be showing before it counts, in logical pixels.
///
/// *Some* of it, not all of it. Requiring the whole row was the old rule and it read
/// as broken: the post you were looking at — the one filling the screen, the one
/// half-showing at the bottom that you had plainly started — kept its unread rail,
/// and a post taller than the viewport could never be marked at all. A row you have
/// scrolled into view is a row you have seen, so the bar is only high enough to
/// exclude the hairline of the next post that is always poking in at the edge.
const seenSlice = 24.0;

/// The rows showing in [viewport], and therefore read.
///
/// A row counts once [minVisible] pixels of it are inside the viewport, or — for a
/// row shorter than that — once all of it is. A row taller than the viewport counts
/// too, which is the point: a wall of text scrolled through has been read the same
/// way a short one has.
Iterable<String> seenRows(
  Map<String, Rect> rows,
  Rect viewport, {
  double minVisible = seenSlice,
}) => [
  for (final MapEntry(key: id, value: box) in rows.entries)
    if (_showing(box, viewport) case final showing
        when showing > 0 && showing >= (box.height < minVisible ? box.height : minVisible))
      id,
];

/// The height of the overlap, or a negative number when there is none.
double _showing(Rect box, Rect viewport) =>
    (box.bottom < viewport.bottom ? box.bottom : viewport.bottom) -
    (box.top > viewport.top ? box.top : viewport.top);
