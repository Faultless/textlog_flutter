/// When an unread row counts as read. Pure so the rule lives in a test, not a device.
library;

import 'dart:ui' show Rect;

/// How much of a row has to show before it counts. Low enough that scrolling a post
/// into view marks it, high enough to exclude the hairline at the screen edge.
const seenSlice = 24.0;

/// The rows showing in [viewport], and therefore read. A row taller than the viewport
/// counts too — it can never be fully inside one.
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

/// Height of the overlap, negative when there is none.
double _showing(Rect box, Rect viewport) =>
    (box.bottom < viewport.bottom ? box.bottom : viewport.bottom) -
    (box.top > viewport.top ? box.top : viewport.top);
