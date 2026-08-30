import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/seen.dart';

const viewport = Rect.fromLTRB(0, 0, 400, 800);

void main() {
  group('what counts as read', () {
    test('a row fully on screen', () {
      expect(seenRows({'a': const Rect.fromLTRB(0, 10, 400, 200)}, viewport), ['a']);
    });

    test('a row hanging off the bottom', () {
      // The rule used to be that the whole row had to be inside, which meant the
      // post you had plainly started reading kept its unread rail until you
      // scrolled it clear. Scrolling it into view is what reading looks like.
      expect(seenRows({'a': const Rect.fromLTRB(0, 700, 400, 900)}, viewport), ['a']);
    });

    test('but not the hairline of the next one poking in', () {
      // Every screen ends mid-post. A few pixels at the edge is the thing you are
      // scrolling towards, and marking it would quietly lose it.
      expect(seenRows({'a': const Rect.fromLTRB(0, 790, 400, 990)}, viewport), isEmpty);
    });

    test('not a row scrolled off the top', () {
      // It may have been read, but it may equally have been jumped past by a fling
      // that landed further down. The row that is *on screen* is the safe claim.
      expect(seenRows({'a': const Rect.fromLTRB(0, -200, 400, -10)}, viewport), isEmpty);
    });

    test('a row taller than the screen', () {
      // It cannot ever be fully inside, so the old rule never marked a wall of text
      // at all — you could scroll through a thousand words and still be told you
      // had not read them.
      expect(seenRows({'a': const Rect.fromLTRB(0, -10, 400, 1000)}, viewport), ['a']);
    });

    test('a row shorter than the slice, once all of it shows', () {
      expect(seenRows({'a': const Rect.fromLTRB(0, 100, 400, 110)}, viewport), ['a']);
      expect(seenRows({'a': const Rect.fromLTRB(0, 795, 400, 805)}, viewport), isEmpty);
    });

    test('a row flush with both edges', () {
      expect(seenRows({'a': const Rect.fromLTRB(0, 0, 400, 800)}, viewport), ['a']);
    });

    test('several at once, and only the ones that qualify', () {
      final seen = seenRows({
        'a': const Rect.fromLTRB(0, 0, 400, 100),
        'b': const Rect.fromLTRB(0, 100, 400, 300),
        'c': const Rect.fromLTRB(0, 750, 400, 950),
        'd': const Rect.fromLTRB(0, 799, 400, 999),
      }, viewport);
      expect(seen, ['a', 'b', 'c']);
    });

    test('nothing at all is not an error', () {
      expect(seenRows(const {}, viewport), isEmpty);
    });
  });
}
