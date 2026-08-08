import 'dart:async';
import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/data/firehose.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/providers.dart';

Map<String, dynamic> raw(int id) => {
  'id': id,
  'body': 'post $id',
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': null,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'api_url': 'https://textlog.cc/api/v1/posts/$id',
  'author': {
    'handle': 'a',
    'url': 'https://textlog.cc/u/a',
    'api_url': 'https://textlog.cc/api/v1/users/a',
  },
};

Post post(int id) => Post.fromJson(raw(id));

/// `latest` is what /feeds/latest will return, and can be changed between reconnects
/// to simulate posts published while the stream was down.
({ProviderContainer container, StreamController<FirehoseEvent> events, void Function(List<int>) setLatest})
harness() {
  final events = StreamController<FirehoseEvent>.broadcast();
  var latest = <int>[];

  final container = ProviderContainer(
    overrides: [
      firehoseProvider.overrideWith((ref) => events.stream),
      httpClientProvider.overrideWithValue(
        MockClient(
          (_) async => http.Response(
            jsonEncode({
              'data': [for (final id in latest) raw(id)],
              'pagination': {'next_cursor': null},
            }),
            200,
          ),
        ),
      ),
    ],
  );
  addTearDown(() {
    container.dispose();
    events.close();
  });
  return (container: container, events: events, setLatest: (ids) => latest = ids);
}

Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 20));

void main() {
  test('the first connection does not tip the backlog into the tab', () async {
    final h = harness();
    h.setLatest([50, 49, 48]);
    h.container.listen(liveFeedProvider, (_, _) {}, fireImmediately: true);

    h.events.add(const FirehoseConnected());
    await settle();

    expect(h.container.read(liveFeedProvider), isEmpty);
  });

  test('a reconnect back-fills only what was published during the gap', () async {
    final h = harness();
    h.setLatest([50]);
    h.container.listen(liveFeedProvider, (_, _) {}, fireImmediately: true);

    h.events.add(const FirehoseConnected());
    await settle();

    // 51 and 52 land while the stream is down; 50 was already there.
    h.setLatest([52, 51, 50]);
    h.events.add(const FirehoseConnected());
    await settle();

    expect(h.container.read(liveFeedProvider).map((p) => p.id), [52, 51]);
  });

  test('a post seen live is not duplicated by the next reconciliation', () async {
    final h = harness();
    h.setLatest([50]);
    h.container.listen(liveFeedProvider, (_, _) {}, fireImmediately: true);

    h.events.add(const FirehoseConnected());
    await settle();

    h.events.add(FirehosePost(post(51)));
    await settle();

    h.setLatest([52, 51, 50]);
    h.events.add(const FirehoseConnected());
    await settle();

    expect(h.container.read(liveFeedProvider).map((p) => p.id), [52, 51]);
  });

  test('the buffer stays newest-first across a merge', () async {
    final h = harness();
    h.setLatest([10]);
    h.container.listen(liveFeedProvider, (_, _) {}, fireImmediately: true);

    h.events.add(const FirehoseConnected());
    await settle();

    h.events.add(FirehosePost(post(13)));
    await settle();

    // 11 and 12 were missed and only surface via reconciliation, out of order.
    h.setLatest([13, 12, 11, 10]);
    h.events.add(const FirehoseConnected());
    await settle();

    expect(h.container.read(liveFeedProvider).map((p) => p.id), [13, 12, 11]);
  });

  test('a live reply drops its parent thread from the cache', () async {
    final h = harness();
    h.setLatest([50]);
    h.container.listen(liveFeedProvider, (_, _) {}, fireImmediately: true);

    // Pretend we are holding thread 40's replies.
    h.container.read(repliesCacheProvider).remember(40, [post(41)], DateTime(2026));
    expect(h.container.read(repliesCacheProvider)[40], isNotNull);

    h.events.add(const FirehoseConnected());
    await settle();
    h.events.add(FirehosePost(Post.fromJson({...raw(60), 'parent_id': 40})));
    await settle();

    expect(
      h.container.read(repliesCacheProvider)[40],
      isNull,
      reason: 'the new reply belongs to thread 40, so what we hold for it is stale',
    );
  });

  test('a failed reconciliation leaves the buffer alone', () async {
    final events = StreamController<FirehoseEvent>.broadcast();
    final container = ProviderContainer(
      overrides: [
        firehoseProvider.overrideWith((ref) => events.stream),
        httpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('nope', 500)),
        ),
      ],
    );
    addTearDown(() {
      container.dispose();
      events.close();
    });

    container.listen(liveFeedProvider, (_, _) {}, fireImmediately: true);
    events.add(const FirehoseConnected());
    events.add(FirehosePost(post(7)));
    await settle();

    expect(container.read(liveFeedProvider).map((p) => p.id), [7]);
  });
}
