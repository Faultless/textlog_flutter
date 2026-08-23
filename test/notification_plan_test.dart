import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/notification_plan.dart';

Post post(int id, {String handle = 'alice', String body = 'hello', int? parentId, Post? parent, List<String> mentions = const []}) => Post(
  id: id,
  body: body,
  createdAt: DateTime(2026, 8, 8),
  parentId: parentId ?? parent?.id,
  replyCount: 0,
  tags: const [],
  mentions: mentions,
  url: Uri.parse('https://textlog.cc/post/$id'),
  author: Author(handle: handle, url: Uri.parse('https://textlog.cc/u/$handle')),
  parent: parent,
);

Activity activity(
  String id, {
  ActivityKind kind = ActivityKind.reply,
  bool unread = true,
  Post? withPost,
  String actor = 'alice',
}) => Activity(
  id: id,
  kind: kind,
  createdAt: DateTime(2026, 8, 8),
  unread: unread,
  post: withPost,
  actor: UserRef(handle: actor, url: Uri.parse('https://textlog.cc/u/$actor')),
);

NotificationPlan plan(
  List<Activity> activities, {
  Set<String> announced = const {},
  NotifyPreferences preferences = NotifyPreferences.defaults,
  String? viewer = 'bob',
}) => planNotifications(
  activities: activities,
  alreadyAnnounced: announced,
  preferences: preferences,
  viewerHandle: viewer,
);

void main() {
  group('what gets announced', () {
    test('a reply to you does', () {
      final result = plan([
        activity('r1', withPost: post(2, parent: post(1, handle: 'bob'))),
      ]);
      expect(result.notifications.single.kind, NotifyKind.replies);
      expect(result.notifications.single.title, '@alice replied to you');
      expect(result.notifications.single.route, '/post/2');
    });

    test('a mention does, and outranks the reply it arrived as', () {
      // Being named is the more specific fact, and it is the switch the reader
      // turned on for exactly this.
      final result = plan([
        activity('m1', withPost: post(2, body: 'hi @bob', mentions: const ['bob'],
            parent: post(1, handle: 'bob'))),
      ]);
      expect(result.notifications.single.kind, NotifyKind.mentions);
      expect(result.notifications.single.title, '@alice replied and mentioned you');
    });

    test('a follow does, with nothing to reply to', () {
      final result = plan([activity('f1', kind: ActivityKind.userFollow)]);
      final only = result.notifications.single;
      expect(only.kind, NotifyKind.follows);
      expect(only.title, '@alice followed you');
      expect(only.canReply, isFalse);
      expect(only.route, '/u/alice');
    });

    test('something already read does not', () {
      // Read on the web, or on another device.
      expect(plan([activity('r1', unread: false, withPost: post(2))]).isEmpty, isTrue);
    });

    test('an unrecognised kind does not', () {
      // A new activity type on the server must not start notifying on its own.
      final result = plan([activity('t1', kind: ActivityKind.tagFollow)]);
      expect(result.isEmpty, isTrue);
    });

    test('nothing does when notifications are off', () {
      final result = plan(
        [activity('r1', withPost: post(2))],
        preferences: NotifyPreferences.off,
      );
      expect(result.isEmpty, isTrue);
      expect(result.announced, isEmpty, reason: 'and nothing is remembered either');
    });
  });

  group('saying it once', () {
    test('an activity announced before is not announced again', () {
      // The poll sees the same page every fifteen minutes.
      final result = plan([activity('r1', withPost: post(2))], announced: {'r1'});
      expect(result.isEmpty, isTrue);
    });

    test('everything considered is remembered, so the next poll is quiet', () {
      final first = plan([
        activity('r1', withPost: post(2)),
        activity('r2', withPost: post(3)),
      ]);
      expect(first.notifications, hasLength(2));

      final second = plan([
        activity('r1', withPost: post(2)),
        activity('r2', withPost: post(3)),
      ], announced: first.announced);
      expect(second.isEmpty, isTrue);
    });

    test('a kind switched off is still remembered', () {
      // Otherwise turning `follows` on later would dredge up every follow since
      // the app was installed.
      final result = plan(
        [activity('f1', kind: ActivityKind.userFollow)],
        preferences: const NotifyPreferences(
          enabled: true,
          kinds: {NotifyKind.replies},
        ),
      );
      expect(result.notifications, isEmpty);
      expect(result.announced, {'f1'});
    });

    test('the same activity always gets the same system id', () {
      final one = plan([activity('r1', withPost: post(2))]).notifications.single;
      final two = plan([activity('r1', withPost: post(2))]).notifications.single;
      expect(one.systemId, two.systemId);
      expect(one.systemId, greaterThanOrEqualTo(0));
    });
  });

  group('not being a nuisance', () {
    test('a backlog is capped', () {
      final many = [
        for (var i = 0; i < 20; i++) activity('r$i', withPost: post(i + 2)),
      ];
      final result = plan(many);
      expect(result.notifications, hasLength(maxNotificationsPerPoll));
      // …but the whole backlog is marked as seen, so it is not announced later.
      expect(result.announced, hasLength(20));
    });

    test('only the kinds asked for are raised', () {
      final result = plan(
        [
          activity('r1', withPost: post(2, parent: post(1, handle: 'bob'))),
          activity('f1', kind: ActivityKind.userFollow),
        ],
        preferences: const NotifyPreferences(enabled: true, kinds: {NotifyKind.follows}),
      );
      expect(result.notifications.single.kind, NotifyKind.follows);
    });
  });

  group('what a notification says', () {
    test('a poll is announced as a poll, without its options', () {
      final result = plan([
        activity('p1', withPost: post(2, body: 'tabs or spaces? #poll\ntabs\nspaces',
            mentions: const ['bob'])),
      ]);
      final only = result.notifications.single;
      expect(only.body, 'tabs or spaces? #poll');
      expect(only.body, isNot(contains('spaces\n')));
    });

    test('a reply carries the post so a quick reply knows its parent', () {
      final result = plan([activity('r1', withPost: post(42))]);
      expect(result.notifications.single.replyToPostId, 42);
      expect(result.notifications.single.canReply, isTrue);
    });

    test('with nobody signed in nothing is about you', () {
      final result = plan([
        activity('r1', withPost: post(2, body: 'hi @bob', mentions: const ['bob'])),
      ], viewer: null);
      // Still a reply — just not one the app can claim was aimed at you.
      expect(result.notifications.single.kind, NotifyKind.replies);
    });
  });

  test('preferences round-trip through their ids', () {
    for (final kind in NotifyKind.values) {
      expect(NotifyKind.fromId(kind.id), kind);
    }
    expect(NotifyKind.fromId('nonsense'), isNull);
    expect(NotifyKind.fromId(null), isNull);
  });
}
