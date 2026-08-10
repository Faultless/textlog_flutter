import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/data/api.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/feed.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/rate_limit.dart';
import 'package:textlog/state/session.dart';
import 'package:textlog/ui/widgets/status.dart';

http.Response limited({int? retryAfter, String body = ''}) => http.Response(
  body.isEmpty ? jsonEncode({'error': {'code': 'rate_limited', 'message': 'Too many'}}) : body,
  429,
  headers: {
    'content-type': 'application/json',
    if (retryAfter != null) 'retry-after': '$retryAfter',
  },
);

Map<String, dynamic> postJson(int id) => {
  'id': id,
  'body': 'post $id',
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': null,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'author': {'handle': 'a', 'url': 'https://textlog.cc/u/a'},
};

String feedPage(List<int> ids, {String? cursor}) => jsonEncode({
  'data': [for (final id in ids) postJson(id)],
  'pagination': {'next_cursor': cursor},
});

void main() {
  test('a rate limited answer carries how long to wait', () async {
    late ApiFailure failure;
    final api = TextlogApi(MockClient((_) async => limited(retryAfter: 90)));
    try {
      await api.me('token');
    } on ApiFailure catch (error) {
      failure = error;
    }

    expect(failure.isRateLimited, isTrue);
    expect(failure.retryAfter, const Duration(seconds: 90));
    expect(messageFor(failure), 'Too many requests. Try again in 2 minutes.');
  });

  test('an error page that is not JSON still reads as its status', () async {
    late ApiFailure failure;
    final api = TextlogApi(
      MockClient((_) async => http.Response('<html>too many</html>', 429, headers: {
        'content-type': 'text/html',
        'retry-after': '30',
      })),
    );
    try {
      await api.me('token');
    } on ApiFailure catch (error) {
      failure = error;
    }

    expect(failure.isRateLimited, isTrue);
    expect(failure.retryAfter, const Duration(seconds: 30));
  });

  test('the gate holds for as long as asked, and never longer than its ceiling', () {
    final gate = RateLimitGate();
    final now = DateTime(2026, 8, 10, 12);

    expect(gate.isTripped(now), isFalse);
    gate.trip(now, const Duration(seconds: 45));
    expect(gate.isTripped(now.add(const Duration(seconds: 44))), isTrue);
    expect(gate.isTripped(now.add(const Duration(seconds: 46))), isFalse);

    gate.trip(now, const Duration(hours: 1));
    expect(gate.isTripped(now.add(const Duration(minutes: 3))), isFalse);

    gate.clear();
    expect(gate.isTripped(now), isFalse);
  });

  test('being rate limited does not sign you out', () async {
    SharedPreferences.setMockInitialValues({
      'session_token': 'token',
      'session_handle': 'me',
    });
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(MockClient((_) async => limited(retryAfter: 60))),
      ],
    );
    addTearDown(container.dispose);

    final session = await container.read(sessionProvider.future);
    expect(session?.account.handle, 'me', reason: 'a limit is not a rejected token');
    expect(
      (await SharedPreferences.getInstance()).getString('session_token'),
      'token',
      reason: 'the stored token survives',
    );
  });

  test('a rejected token does sign you out', () async {
    SharedPreferences.setMockInitialValues({
      'session_token': 'token',
      'session_handle': 'me',
    });
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response(
            jsonEncode({'error': {'code': 'unauthorized', 'message': 'no'}}),
            401,
            headers: {'content-type': 'application/json'},
          )),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(sessionProvider.future), isNull);
    expect((await SharedPreferences.getInstance()).getString('session_token'), isNull);
  });

  test('scrolling past a failed page does not keep asking', () async {
    var calls = 0;
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            calls++;
            if (request.url.queryParameters['cursor'] == null) {
              return http.Response(feedPage([1, 2], cursor: 'next'), 200,
                  headers: {'content-type': 'application/json'});
            }
            return limited(retryAfter: 60);
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    const source = LatestFeed();
    await container.read(feedProvider(source).future);
    expect(calls, 1);

    final notifier = container.read(feedProvider(source).notifier);
    await notifier.loadMore();
    expect(calls, 2);
    expect(container.read(feedProvider(source)).valueOrNull?.loadMoreError, isNotNull);

    // What the scroll listener does, over and over, at the bottom of the list.
    for (var i = 0; i < 5; i++) {
      await notifier.loadMore();
    }
    expect(calls, 2, reason: 'the failed page is not retried on its own');

    await notifier.loadMore(asked: true);
    expect(calls, 3, reason: 'tapping retry still asks');
  });

  test('a tripped limit holds back paging nobody asked for', () async {
    var calls = 0;
    final gate = RateLimitGate();
    final container = ProviderContainer(
      overrides: [
        rateLimitProvider.overrideWithValue(gate),
        httpClientProvider.overrideWithValue(
          MockClient((_) async {
            calls++;
            return http.Response(feedPage([1, 2], cursor: 'next'), 200,
                headers: {'content-type': 'application/json'});
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    const source = LatestFeed();
    await container.read(feedProvider(source).future);
    expect(calls, 1);

    gate.trip(container.read(nowProvider)(), const Duration(seconds: 60));
    await container.read(feedProvider(source).notifier).loadMore();
    expect(calls, 1);

    gate.clear();
    await container.read(feedProvider(source).notifier).loadMore();
    expect(calls, 2);
  });

  test('waits are spelled out in words a reader can act on', () {
    expect(humanDuration(const Duration(seconds: 5)), '5 seconds');
    expect(humanDuration(const Duration(seconds: 61)), '2 minutes');
    expect(humanDuration(const Duration(minutes: 1)), '1 minute');
    expect(humanDuration(const Duration(hours: 1)), '1 hour');
  });
}
