import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/data/feed_store.dart';
import 'package:textlog/data/local_store.dart';
import 'package:textlog/state/feed.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/session.dart';

Map<String, dynamic> post(int id, {String body = 'stored'}) => {
  'id': id,
  'body': body,
  'created_at': '2026-08-26T08:00:00.000Z',
  'parent_id': null,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'author': {'handle': 'a', 'url': 'https://textlog.cc/u/a'},
};

Map<String, dynamic> page(List<Map<String, dynamic>> posts, {String? cursor}) => {
  'data': posts,
  'pagination': {'next_cursor': cursor},
};

void main() {
  setUp(FeedNotifier.forgetColdStarts);

  group('the session at cold start', () {
    test('is already signed in when the device knows the account', () async {
      // The whole complaint: the app used to open signed out and change its mind,
      // because the session was read asynchronously and then confirmed over the
      // network before anything rendered.
      SharedPreferences.setMockInitialValues({
        'session_token': 'tok',
        'session_handle': 'me',
      });
      await LocalStore.prime();

      final container = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response('{"data":{}}', 500)),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Read synchronously, exactly as the first frame does.
      final immediately = container.read(viewerProvider);
      expect(immediately, isNotNull, reason: 'no waiting, no flash of signed out');
      expect(immediately!.account.handle, 'me');
      expect(container.read(viewerHandleProvider), 'me');
    });

    test('and signed out when it does not', () async {
      SharedPreferences.setMockInitialValues({});
      await LocalStore.prime();

      final container = ProviderContainer();
      addTearDown(container.dispose);
      expect(container.read(viewerProvider), isNull);
    });

    test('the confirmation fills in the rest of the account', () async {
      SharedPreferences.setMockInitialValues({
        'session_token': 'tok',
        'session_handle': 'me',
      });
      await LocalStore.prime();

      final container = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response(
              jsonEncode({
                'data': {'handle': 'me', 'bio': 'a real bio', 'can_post': true},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      // The stored copy is only a handle — that is all the background poller needed.
      expect(container.read(viewerProvider)!.account.bio, '');
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(viewerProvider)!.account.bio, 'a real bio');
    });

    test('being offline is not evidence that anyone signed out', () async {
      SharedPreferences.setMockInitialValues({
        'session_token': 'tok',
        'session_handle': 'me',
      });
      await LocalStore.prime();

      final container = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(
            MockClient((_) async => throw http.ClientException('offline')),
          ),
        ],
      );
      addTearDown(container.dispose);

      expect(container.read(viewerProvider), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(viewerProvider), isNotNull);
    });

    test('a rejected token does sign you out', () async {
      SharedPreferences.setMockInitialValues({
        'session_token': 'stale',
        'session_handle': 'me',
      });
      await LocalStore.prime();

      final container = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(
            MockClient((_) async => http.Response(
              '{"error":{"code":"unauthorized","message":"no"}}',
              401,
              headers: {'content-type': 'application/json; charset=utf-8'},
            )),
          ),
        ],
      );
      addTearDown(container.dispose);

      // Signed in as far as the device knows, until the server says otherwise.
      expect(container.read(viewerProvider), isNotNull);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(container.read(viewerProvider), isNull);
      // And the token is gone, so the next cold start does not offer it again.
      expect(LocalStore.primedSession(), isNull);
    });
  });

  group('the feed at cold start', () {
    test('shows what was stored, then replaces it', () async {
      SharedPreferences.setMockInitialValues({});
      await FeedStore.save('feed:latest', page([post(1, body: 'from yesterday')]));

      var served = 0;
      final container = ProviderContainer(
        overrides: [
          httpClientProvider.overrideWithValue(
            MockClient((_) async {
              served++;
              return http.Response(
                jsonEncode(page([post(2, body: 'fresh')])),
                200,
                headers: {'content-type': 'application/json; charset=utf-8'},
              );
            }),
          ),
        ],
      );
      addTearDown(container.dispose);

      final first = await container.read(feedProvider(const LatestFeed()).future);
      expect(first.posts.single.body, 'from yesterday');

      // …and the network lands behind it, in place rather than by rebuilding, which
      // would read the stored page again and revalidate forever.
      await Future<void>.delayed(const Duration(milliseconds: 80));
      expect(
        container.read(feedProvider(const LatestFeed())).valueOrNull!.posts.single.body,
        'fresh',
      );
      expect(served, 1);
    });

    test('a page past its shelf life is not shown', () async {
      // Posts carry a relative timestamp, and `3h` on a week-old post is a lie.
      SharedPreferences.setMockInitialValues({});
      await FeedStore.save(
        'feed:latest',
        page([post(1)]),
        now: DateTime(2026, 8, 1),
      );
      expect(await FeedStore.load('feed:latest', now: DateTime(2026, 8, 26)), isNull);
      expect(await FeedStore.load('feed:latest', now: DateTime(2026, 8, 1, 6)), isNotNull);
    });

    test('only the feeds a cold start can open on are kept', () {
      expect(coldStorageKeyOf(const LatestFeed()), 'feed:latest');
      expect(coldStorageKeyOf(const HotFeed()), 'feed:hot');
      // Activity is not worth a stale copy, and neither is every tag anyone opened.
      expect(coldStorageKeyOf(const TagFeed('flutter')), isNull);
      expect(coldStorageKeyOf(const SearchFeed('x')), isNull);
    });

    test('a fetched page is kept for next time, trimmed', () async {
      SharedPreferences.setMockInitialValues({});
      await FeedStore.save(
        'feed:hot',
        page([for (var i = 1; i <= 40; i++) post(i)], cursor: 'more'),
      );
      final stored = (await FeedStore.load('feed:hot'))!;
      expect((stored['data'] as List).length, FeedStore.limit);
      // The cursor belonged to the whole page; keeping it would page from the wrong
      // place and skip everything that was trimmed off.
      expect((stored['pagination'] as Map)['next_cursor'], isNull);
    });

    test('nonsense on disk is thrown away rather than crashing', () async {
      SharedPreferences.setMockInitialValues({
        'feed:latest': 'not json at all',
        'feed:latest:saved_at': DateTime.now().millisecondsSinceEpoch,
      });
      expect(await FeedStore.load('feed:latest'), isNull);
    });
  });
}
