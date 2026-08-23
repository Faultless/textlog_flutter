import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/drafts.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/session.dart';

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

Map<String, dynamic> postJson(int id, {int? parentId}) => {
  'id': id,
  'top_id': null,
  'body': 'post $id',
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': parentId,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'api_url': 'https://textlog.cc/api/v1/posts/$id',
  'author': {
    'handle': 'me',
    'url': 'https://textlog.cc/u/me',
    'api_url': 'https://textlog.cc/api/v1/users/me',
  },
  'parent': null,
};

Map<String, dynamic> draftJson(int id, {String body = 'half a thought', int? parentId}) => {
  'id': id,
  'body': body,
  'parent_id': parentId,
  'created_at': '2026-08-08T08:00:00.000Z',
  'updated_at': '2026-08-08T09:00:00.000Z',
  'parent': parentId == null ? null : postJson(parentId),
};

({ProviderContainer container, List<String> calls, List<String> bodies}) harness({
  List<Map<String, dynamic>> drafts = const [],
  bool signedIn = true,
  bool failWrites = false,
}) {
  final calls = <String>[];
  final bodies = <String>[];
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(signedIn ? FakeSession.new : NoSession.new),
      httpClientProvider.overrideWithValue(
        MockClient((request) async {
          calls.add('${request.method} ${request.url.path}');
          if (request.method != 'GET') bodies.add(request.body);
          if (failWrites && request.method != 'GET') {
            return http.Response('{"error":{"code":"x","message":"no"}}', 500);
          }
          if (request.url.path.endsWith('/publish')) {
            return http.Response(jsonEncode({'data': postJson(99)}), 200);
          }
          if (request.method == 'GET' && request.url.path.endsWith('/drafts')) {
            return http.Response(
              jsonEncode({'data': drafts, 'pagination': {'next_cursor': null}}),
              200,
            );
          }
          if (request.method == 'DELETE') {
            return http.Response('{"data":{"deleted":true}}', 200);
          }
          return http.Response(jsonEncode({'data': draftJson(7, body: 'saved')}), 200);
        }),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, calls: calls, bodies: bodies);
}

void main() {
  test('a draft list decodes, newest first as the server sends it', () async {
    final t = harness(drafts: [draftJson(2), draftJson(1)]);
    final list = await t.container.read(draftsProvider.future);

    expect(list.map((draft) => draft.id), [2, 1]);
    expect(t.container.read(draftCountProvider), 2);
  });

  test("a reply draft keeps the post it answers, and caches it", () async {
    // So opening it shows its context without another fetch.
    final t = harness(drafts: [draftJson(2, parentId: 50)]);
    final list = await t.container.read(draftsProvider.future);

    expect(list.single.isReply, isTrue);
    expect(list.single.parent!.id, 50);
    expect(t.container.read(postCacheProvider)[50], isNotNull);
  });

  test('saving one puts it at the top of the list', () async {
    final t = harness(drafts: [draftJson(1)]);
    await t.container.read(draftsProvider.future);

    await t.container.read(draftsProvider.notifier).save('something new');

    expect(t.container.read(draftsProvider).value!.map((d) => d.id), [7, 1]);
    expect(jsonDecode(t.bodies.single), {'body': 'something new', 'parent_id': null});
  });

  test('publishing consumes it', () async {
    // The server turns the draft into a post, so a copy must not linger beside it.
    final t = harness(drafts: [draftJson(3)]);
    await t.container.read(draftsProvider.future);

    final post = await t.container.read(draftsProvider.notifier).publish(3);

    expect(post!.id, 99);
    expect(t.container.read(draftsProvider).value, isEmpty);
    expect(t.calls, contains('POST /api/v1/drafts/3/publish'));
    expect(t.container.read(postCacheProvider)[99], isNotNull);
  });

  test('discarding takes it off the list before the server agrees', () async {
    final t = harness(drafts: [draftJson(4), draftJson(5)]);
    await t.container.read(draftsProvider.future);

    final pending = t.container.read(draftsProvider.notifier).discard(4);
    expect(
      t.container.read(draftsProvider).value!.map((d) => d.id),
      [5],
      reason: 'a row that lingers reads as the tap not working',
    );
    await pending;
    expect(t.calls, contains('DELETE /api/v1/drafts/4'));
  });

  test('a failed discard puts it back', () async {
    final t = harness(drafts: [draftJson(4)], failWrites: true);
    await t.container.read(draftsProvider.future);

    await expectLater(
      t.container.read(draftsProvider.notifier).discard(4),
      throwsA(isA<ApiFailure>()),
    );
    expect(t.container.read(draftsProvider).value!.map((d) => d.id), [4]);
  });

  test('editing replaces it in place', () async {
    final t = harness(drafts: [draftJson(7, body: 'before')]);
    await t.container.read(draftsProvider.future);

    await t.container.read(draftsProvider.notifier).edit(7, 'after');

    expect(t.container.read(draftsProvider).value!.single.body, 'saved');
    expect(jsonDecode(t.bodies.single), {'body': 'after'});
  });

  test('without a session there is nothing to list and nothing to ask', () async {
    final t = harness(signedIn: false);
    expect(await t.container.read(draftsProvider.future), isEmpty);
    expect(t.calls, isEmpty);
  });
}
