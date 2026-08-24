import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/seen.dart';

const viewport = Rect.fromLTRB(0, 0, 400, 800);

void main() {
  group('what counts as read', () {
    test('a row fully on screen', () {
      expect(seenRows({'a': const Rect.fromLTRB(0, 10, 400, 200)}, viewport), ['a']);
    });

    test('not a row hanging off the bottom', () {
      // Half a row showing is the thing you were scrolling towards, not the thing
      // you just read. Marking it would lose it.
      expect(seenRows({'a': const Rect.fromLTRB(0, 700, 400, 900)}, viewport), isEmpty);
    });

    test('not a row scrolled off the top', () {
      // It may have been read, but it may equally have been jumped past by a fling
      // that landed further down. The row that is *on screen* is the safe claim.
      expect(seenRows({'a': const Rect.fromLTRB(0, -200, 400, -10)}, viewport), isEmpty);
    });

    test('not a row taller than the screen', () {
      // A wall of text should never be declared read because it happened to pass by.
      expect(seenRows({'a': const Rect.fromLTRB(0, -10, 400, 1000)}, viewport), isEmpty);
    });

    test('a row flush with both edges', () {
      expect(seenRows({'a': const Rect.fromLTRB(0, 0, 400, 800)}, viewport), ['a']);
    });

    test('several at once, and only the ones that qualify', () {
      final seen = seenRows({
        'a': const Rect.fromLTRB(0, 0, 400, 100),
        'b': const Rect.fromLTRB(0, 100, 400, 300),
        'c': const Rect.fromLTRB(0, 750, 400, 950),
      }, viewport);
      expect(seen, ['a', 'b']);
    });

    test('nothing at all is not an error', () {
      expect(seenRows(const {}, viewport), isEmpty);
    });
  });
}
