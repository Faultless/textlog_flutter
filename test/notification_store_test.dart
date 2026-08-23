import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/notification_plan.dart';
import 'package:textlog/data/local_store.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  group('the session both isolates read', () {
    test('round-trips', () async {
      await LocalStore.saveSession('tok', 'me');
      expect(await LocalStore.token(), 'tok');
      expect(await LocalStore.handle(), 'me');
    });

    test('is gone after signing out', () async {
      await LocalStore.saveSession('tok', 'me');
      await LocalStore.clearSession();
      expect(await LocalStore.token(), isNull);
      expect(await LocalStore.handle(), isNull);
    });

    test('reads what the session notifier wrote under its old keys', () async {
      // The keys moved out of SessionNotifier into LocalStore so the background
      // isolate could read them. An existing install must not be signed out by that.
      SharedPreferences.setMockInitialValues({
        'session_token': 'existing',
        'session_handle': 'someone',
      });
      expect(await LocalStore.token(), 'existing');
      expect(await LocalStore.handle(), 'someone');
    });
  });

  group('preferences', () {
    test('default to off, with every kind ready for when they are turned on', () async {
      final preferences = await LocalStore.preferences();
      expect(preferences.enabled, isFalse);
      expect(preferences.kinds, NotifyPreferences.defaults.kinds);
      expect(preferences.wants(NotifyKind.replies), isFalse, reason: 'off is off');
    });

    test('round-trip', () async {
      await LocalStore.savePreferences(
        const NotifyPreferences(enabled: true, kinds: {NotifyKind.mentions}),
      );
      final read = await LocalStore.preferences();
      expect(read.enabled, isTrue);
      expect(read.kinds, {NotifyKind.mentions});
      expect(read.wants(NotifyKind.mentions), isTrue);
      expect(read.wants(NotifyKind.replies), isFalse);
    });

    test('an empty set is kept, not mistaken for unset', () async {
      // Turning every kind off is a choice, and must not silently turn them all on.
      await LocalStore.savePreferences(const NotifyPreferences(enabled: true));
      expect((await LocalStore.preferences()).kinds, isEmpty);
    });

    test('an id the app no longer knows is ignored', () async {
      SharedPreferences.setMockInitialValues({
        'notify_enabled': true,
        'notify_kinds': ['replies', 'something_removed'],
      });
      expect((await LocalStore.preferences()).kinds, {NotifyKind.replies});
    });
  });

  group('what has already been announced', () {
    test('is remembered across polls', () async {
      await LocalStore.remember({'a', 'b'});
      expect(await LocalStore.announced(), {'a', 'b'});
      await LocalStore.remember({'c'});
      expect(await LocalStore.announced(), {'a', 'b', 'c'});
    });

    test('re-remembering something does not duplicate it', () async {
      await LocalStore.remember({'a'});
      await LocalStore.remember({'a'});
      expect(await LocalStore.announced(), {'a'});
    });

    test('is bounded, dropping the oldest', () async {
      // A phone left running for a year must not accumulate forever.
      await LocalStore.remember({for (var i = 0; i < LocalStore.announcedLimit + 50; i++) 'id$i'});
      final held = await LocalStore.announced();
      expect(held, hasLength(LocalStore.announcedLimit));
      expect(held, contains('id${LocalStore.announcedLimit + 49}'), reason: 'newest kept');
      expect(held, isNot(contains('id0')), reason: 'oldest dropped');
    });

    test('remembering nothing is a no-op', () async {
      await LocalStore.remember({'a'});
      await LocalStore.remember({});
      expect(await LocalStore.announced(), {'a'});
    });

    test('is forgotten on sign out, so signing back in is quiet', () async {
      await LocalStore.remember({'a', 'b'});
      await LocalStore.forgetAnnounced();
      expect(await LocalStore.announced(), isEmpty);
    });
  });

  group('the baseline', () {
    test('is not taken until it is taken', () async {
      expect(await LocalStore.primed(), isFalse);
      await LocalStore.markPrimed();
      expect(await LocalStore.primed(), isTrue);
    });

    test('is cleared on sign out, so signing back in starts from then', () async {
      // Otherwise a return after a week announces the week.
      await LocalStore.markPrimed();
      await LocalStore.remember({'a'});
      await LocalStore.forgetAnnounced();
      expect(await LocalStore.primed(), isFalse);
      expect(await LocalStore.announced(), isEmpty);
    });
  });
}
