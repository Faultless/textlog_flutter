import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/data/api.dart';
import 'package:textlog/state/activity.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/session.dart';

Map<String, dynamic> postPayload(int id, {String handle = 'a'}) => {
  'id': id,
  'top_id': null,
  'body': 'post $id',
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': null,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'api_url': 'https://textlog.cc/api/v1/posts/$id',
  'author': {
    'handle': handle,
    'url': 'https://textlog.cc/u/$handle',
    'api_url': 'https://textlog.cc/api/v1/users/$handle',
  },
  'parent': null,
};

Map<String, dynamic> row(String id, {required bool unread, Map<String, dynamic>? payload}) => {
  'id': id,
  'type': payload == null ? 'user_follow' : 'post',
  'created_at': '2026-08-08T08:00:00.000Z',
  'unread': unread,
  'payload': payload ??
      {
        'actor': {
          'handle': 'b',
          'url': 'https://textlog.cc/u/b',
          'api_url': 'https://textlog.cc/api/v1/users/b',
        },
      },
};

final _session = Session(
  token: 'tok',
  expiresAt: DateTime(2027),
  account: const Account(handle: 'me', bio: '', canPost: true),
);

class FakeSession extends SessionNotifier {
  @override
  Future<Session?> build() async => _session;
}

class NoSession extends SessionNotifier {
  @override
  Future<Session?> build() async => null;
}

({ProviderContainer container, List<String> calls, List<String> bodies}) harness({
  required List<Map<String, dynamic>> rows,
  bool hasUnread = true,
  String? nextCursor,
  bool failWrites = false,
}) {
  final calls = <String>[];
  final bodies = <String>[];
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(FakeSession.new),
      httpClientProvider.overrideWithValue(
        MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.method == 'POST') {
            bodies.add(request.body);
            if (failWrites) return http.Response('{"error":{"code":"x","message":"no"}}', 500);
            return http.Response('{"data":{}}', 200);
          }
          return http.Response(
            jsonEncode({
              'data': rows,
              'has_unread': hasUnread,
              'pagination': {'next_cursor': nextCursor},
            }),
            200,
          );
        }),
      ),
    ],
  );
  // Hold the autoDispose providers open for the length of the test, the way a
  // mounted screen would.
  container.listen(activityProvider(ActivityScope.forYou), (_, _) {}, fireImmediately: true);
  container.listen(activityProvider(ActivityScope.toMe), (_, _) {}, fireImmediately: true);
  addTearDown(container.dispose);
  return (container: container, calls: calls, bodies: bodies);
}

void main() {
  test('decodes a post row and a relationship row differently', () async {
    final t = harness(
      rows: [row('post:1', unread: true, payload: postPayload(1)), row('follow:1', unread: false)],
    );
    final state = await t.container.read(activityProvider(ActivityScope.forYou).future);

    expect(state.items, hasLength(2));
    expect(state.items.first.post!.id, 1);
    expect(state.items.first.kind, ActivityKind.post);
    expect(state.items.last.post, isNull);
    expect(state.items.last.actor!.handle, 'b');
    expect(state.items.last.kind, ActivityKind.userFollow);
  });

  test('asks the right feed for each scope', () async {
    final t = harness(rows: []);
    await t.container.read(activityProvider(ActivityScope.forYou).future);
    await t.container.read(activityProvider(ActivityScope.toMe).future);

    expect(t.calls, [
      'GET /api/v1/activities/for-you',
      'GET /api/v1/activities/to-me',
    ]);
  });

  test('the posts it carries land in the shared cache', () async {
    // An activity row is a whole post, so tapping into its thread should be free.
    final t = harness(rows: [row('post:7', unread: true, payload: postPayload(7))]);
    await t.container.read(activityProvider(ActivityScope.forYou).future);

    expect(t.container.read(postCacheProvider)[7], isNotNull);
  });

  test('has_unread drives the tab marker', () async {
    final unread = harness(rows: [row('a', unread: true)], hasUnread: true);
    await unread.container.read(activityProvider(ActivityScope.forYou).future);
    expect(unread.container.read(activityUnreadProvider(ActivityScope.forYou)), isTrue);

    final read = harness(rows: [row('a', unread: false)], hasUnread: false);
    await read.container.read(activityProvider(ActivityScope.forYou).future);
    expect(read.container.read(activityUnreadProvider(ActivityScope.forYou)), isFalse);
  });

  group('marking read', () {
    test('happens on screen before the server hears about it', () async {
      final t = harness(rows: [row('a', unread: true), row('b', unread: true)]);
      final notifier = t.container.read(activityProvider(ActivityScope.forYou).notifier);
      await t.container.read(activityProvider(ActivityScope.forYou).future);

      final pending = notifier.markRead(['a']);
      // Not awaited yet: the row is already read as far as the reader is concerned.
      expect(
        t.container.read(activityProvider(ActivityScope.forYou)).value!.items.first.unread,
        isFalse,
      );
      await pending;

      expect(t.calls.last, 'POST /api/v1/activities/for-you/read');
      expect(jsonDecode(t.bodies.single), {'activity_ids': ['a']});
    });

    test('leaves the others alone', () async {
      final t = harness(rows: [row('a', unread: true), row('b', unread: true)]);
      final notifier = t.container.read(activityProvider(ActivityScope.forYou).notifier);
      await t.container.read(activityProvider(ActivityScope.forYou).future);
      await notifier.markRead(['a']);

      final items = t.container.read(activityProvider(ActivityScope.forYou)).value!.items;
      expect(items.map((item) => item.unread), [false, true]);
    });

    test('a row that was already read costs no request', () async {
      final t = harness(rows: [row('a', unread: false)]);
      final notifier = t.container.read(activityProvider(ActivityScope.forYou).notifier);
      await t.container.read(activityProvider(ActivityScope.forYou).future);
      final before = t.calls.length;

      await notifier.markRead(['a']);
      expect(t.calls.length, before);
    });

    test('a failure puts the highlight back', () async {
      // The server still thinks it is unread, so showing it as read would be a lie.
      final t = harness(rows: [row('a', unread: true)], failWrites: true);
      final notifier = t.container.read(activityProvider(ActivityScope.forYou).notifier);
      await t.container.read(activityProvider(ActivityScope.forYou).future);

      await notifier.markRead(['a']);
      expect(
        t.container.read(activityProvider(ActivityScope.forYou)).value!.items.single.unread,
        isTrue,
      );
    });

    test('mark all clears every row and the marker', () async {
      final t = harness(rows: [row('a', unread: true), row('b', unread: true)]);
      final notifier = t.container.read(activityProvider(ActivityScope.forYou).notifier);
      await t.container.read(activityProvider(ActivityScope.forYou).future);

      await notifier.markAllRead();

      final state = t.container.read(activityProvider(ActivityScope.forYou)).value!;
      expect(state.items.every((item) => !item.unread), isTrue);
      expect(state.hasUnread, isFalse);
      expect(t.calls.last, 'POST /api/v1/activities/for-you/read-all');
    });

    test('a failed mark all restores everything', () async {
      final t = harness(rows: [row('a', unread: true)], failWrites: true);
      final notifier = t.container.read(activityProvider(ActivityScope.forYou).notifier);
      await t.container.read(activityProvider(ActivityScope.forYou).future);

      await notifier.markAllRead();
      final state = t.container.read(activityProvider(ActivityScope.forYou)).value!;
      expect(state.items.single.unread, isTrue);
      expect(state.hasUnread, isTrue);
    });

    test('the server takes a hundred at a time', () async {
      final many = [for (var i = 0; i < 250; i++) row('id$i', unread: true)];
      final t = harness(rows: many);
      final notifier = t.container.read(activityProvider(ActivityScope.forYou).notifier);
      await t.container.read(activityProvider(ActivityScope.forYou).future);

      await notifier.markRead(many.map((row) => row['id'] as String));

      expect(t.bodies, hasLength(3));
      expect((jsonDecode(t.bodies.first)['activity_ids'] as List), hasLength(100));
      expect((jsonDecode(t.bodies.last)['activity_ids'] as List), hasLength(50));
    });
  });

  test('paginates and keeps what is already on screen', () async {
    final t = harness(rows: [row('a', unread: true)], nextCursor: 'more');
    final notifier = t.container.read(activityProvider(ActivityScope.forYou).notifier);
    await t.container.read(activityProvider(ActivityScope.forYou).future);

    await notifier.loadMore();
    expect(t.container.read(activityProvider(ActivityScope.forYou)).value!.items, hasLength(2));
  });

  test('without a token there is nothing to show and nothing to ask', () async {
    final calls = <String>[];
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(NoSession.new),
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            calls.add(request.url.path);
            return http.Response('{}', 200);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    final state = await container.read(activityProvider(ActivityScope.forYou).future);
    expect(state.items, isEmpty);
    expect(calls.where((path) => path.contains('activities')), isEmpty);
  });
}
