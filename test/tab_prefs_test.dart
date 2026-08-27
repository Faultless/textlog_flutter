import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/tab_prefs.dart';

List<String> arrange(
  List<String> available, {
  List<String> order = const [],
  Set<String> hidden = const {},
}) => arrangeTabs(available, order: order, hidden: hidden, id: (t) => t);

void main() {
  group('the reader’s tab arrangement', () {
    test('no preference means as shipped', () {
      expect(arrange(['hot', 'latest', 'live']), ['hot', 'latest', 'live']);
    });

    test('a stored order is honoured', () {
      expect(
        arrange(['hot', 'latest', 'live'], order: ['live', 'hot', 'latest']),
        ['live', 'hot', 'latest'],
      );
    });

    test('a tab added by a later version is appended, not lost', () {
      // Otherwise anyone who had ever touched this setting would never see a new
      // tab, and it would read as a broken upgrade rather than a stale preference.
      expect(
        arrange(['hot', 'latest', 'brand-new'], order: ['latest', 'hot']),
        ['latest', 'hot', 'brand-new'],
      );
    });

    test('a tab that no longer exists is dropped', () {
      // A stored order can name `for you` from a session when you were signed in.
      expect(
        arrange(['hot', 'latest'], order: ['for-you', 'latest', 'hot']),
        ['latest', 'hot'],
      );
    });

    test('hidden tabs go', () {
      expect(arrange(['hot', 'latest', 'live'], hidden: {'latest'}), ['hot', 'live']);
    });

    test('hiding everything still leaves one', () {
      // A tab row with no tabs is a dead app, with no way back to the setting that
      // broke it.
      expect(
        arrange(['hot', 'latest'], order: ['latest', 'hot'], hidden: {'hot', 'latest'}),
        ['latest'],
      );
    });

    test('hiding one that is not there changes nothing', () {
      expect(arrange(['hot'], hidden: {'live'}), ['hot']);
    });
  });
}
