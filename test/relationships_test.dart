import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/relationships.dart';
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

String page(List<String> handles, {String? next}) => jsonEncode({
  'data': [
    for (final handle in handles)
      {
        'handle': handle,
        'url': 'https://textlog.cc/u/$handle',
        'api_url': 'https://textlog.cc/api/v1/users/$handle',
      },
  ],
  'pagination': {'next_cursor': next},
});

/// A server that hands out `following` and `blocks` lists, optionally longer than
/// the walk is allowed to follow.
String tagPage(List<String> tags, {String? next}) => jsonEncode({
  'data': [
    for (final tag in tags)
      {
        'tag': tag,
        'post_count': 1,
        'follower_count': 1,
        'url': 'https://textlog.cc/tag/$tag',
        'api_url': 'https://textlog.cc/api/v1/tags/$tag',
      },
  ],
  'pagination': {'next_cursor': next},
});

({ProviderContainer container, List<String> calls}) harness({
  List<String> following = const [],
  List<String> blocked = const [],
  List<String> tags = const [],
  bool endlessFollowing = false,
  bool blocksFail = false,
  bool signedIn = true,
}) {
  final calls = <String>[];
  final container = ProviderContainer(
    overrides: [
      sessionProvider.overrideWith(signedIn ? FakeSession.new : NoSession.new),
      httpClientProvider.overrideWithValue(
        MockClient((request) async {
          calls.add(request.url.path);
          if (request.url.path.endsWith('/blocks')) {
            return blocksFail
                ? http.Response('{"error":{"code":"x","message":"no"}}', 500)
                : http.Response(page(blocked), 200);
          }
          if (request.url.path.endsWith('/following/tags')) {
            return http.Response(tagPage(tags), 200);
          }
          return http.Response(
            page(following, next: endlessFollowing ? 'more' : null),
            200,
          );
        }),
      ),
    ],
  );
  addTearDown(container.dispose);
  return (container: container, calls: calls);
}

void main() {
  test('a followed account is known to be followed', () async {
    final t = harness(following: ['alice']);
    await t.container.read(relationshipsProvider.future);

    expect(t.container.read(followsProvider('alice')), isTrue);
  });

  test('an account missing from a complete list is known not to be', () async {
    final t = harness(following: ['alice']);
    await t.container.read(relationshipsProvider.future);

    expect(t.container.read(followsProvider('bob')), isFalse);
  });

  test('an account missing from a truncated list is unknown, not absent', () async {
    // Guessing "not following" for somebody you followed years ago would make the
    // button actively wrong. Saying nothing is the honest answer.
    final t = harness(following: ['alice'], endlessFollowing: true);
    await t.container.read(relationshipsProvider.future);

    expect(t.container.read(followsProvider('alice')), isTrue);
    expect(t.container.read(followsProvider('bob')), isNull);
  });

  test('the walk is capped', () async {
    final t = harness(following: ['alice'], endlessFollowing: true);
    await t.container.read(relationshipsProvider.future);

    // A list walk shares a rate limit with reading, so it is bounded.
    final followingCalls = t.calls.where((path) => path.endsWith('/following/users'));
    expect(followingCalls, hasLength(maxRelationshipPages));
  });

  test('blocks are read with the token', () async {
    final t = harness(blocked: ['spammer']);
    await t.container.read(relationshipsProvider.future);

    expect(t.container.read(blocksProvider('spammer')), isTrue);
    expect(t.calls, contains('/api/v1/users/me/blocks'));
  });

  test('nothing is known without a session, and nothing is asked', () async {
    final t = harness(signedIn: false);
    await t.container.read(relationshipsProvider.future);

    expect(t.container.read(followsProvider('alice')), isNull);
    expect(t.calls, isEmpty);
  });

  test('a failure is unknown rather than an error screen', () async {
    final container = ProviderContainer(
      overrides: [
        sessionProvider.overrideWith(FakeSession.new),
        httpClientProvider.overrideWithValue(
          MockClient((_) async => http.Response('nope', 500)),
        ),
      ],
    );
    addTearDown(container.dispose);

    final relationships = await container.read(relationshipsProvider.future);
    expect(relationships.followingComplete, isFalse);
    expect(container.read(followsProvider('alice')), isNull);
  });

  group('acting on an account settles it', () {
    test('following one we did not know about', () async {
      final t = harness(following: ['alice'], endlessFollowing: true);
      await t.container.read(relationshipsProvider.future);
      expect(t.container.read(followsProvider('bob')), isNull);

      t.container.read(relationshipsProvider.notifier).noteFollow('bob', following: true);
      expect(t.container.read(followsProvider('bob')), isTrue);
    });

    test('unfollowing is knowledge even when the list stopped short', () async {
      final t = harness(following: ['alice'], endlessFollowing: true);
      await t.container.read(relationshipsProvider.future);

      t.container.read(relationshipsProvider.notifier).noteFollow('alice', following: false);
      // Not null: we just did it.
      expect(t.container.read(followsProvider('alice')), isFalse);
    });

    test('blocking drops the follow with it, as the server does', () async {
      final t = harness(following: ['alice']);
      await t.container.read(relationshipsProvider.future);
      expect(t.container.read(followsProvider('alice')), isTrue);

      t.container.read(relationshipsProvider.notifier).noteBlock('alice', blocked: true);
      expect(t.container.read(blocksProvider('alice')), isTrue);
      expect(t.container.read(followsProvider('alice')), isFalse);
    });

    test('unblocking is remembered', () async {
      final t = harness(blocked: ['spammer']);
      await t.container.read(relationshipsProvider.future);

      t.container.read(relationshipsProvider.notifier).noteBlock('spammer', blocked: false);
      expect(t.container.read(blocksProvider('spammer')), isFalse);
    });
  });

  group('followed hashtags', () {
    test('are not fetched until something asks', () async {
      // Only a hashtag screen ever needs them, and folding them into the account
      // lists would make every follow button on a profile pay for a list it cannot use.
      final t = harness(following: ['alice'], tags: ['ascii']);
      await t.container.read(relationshipsProvider.future);

      expect(t.calls.any((path) => path.endsWith('/following/tags')), isFalse);
    });

    test('answer once they are', () async {
      final t = harness(tags: ['ascii', 'dart']);
      await t.container.read(followedTagSetProvider.future);

      expect(t.container.read(followsTagProvider('ascii')), isTrue);
      expect(t.container.read(followsTagProvider('flutter')), isFalse);
      expect(t.calls, contains('/api/v1/users/me/following/tags'));
    });

    test('acting on one settles it', () async {
      final t = harness(tags: const []);
      await t.container.read(followedTagSetProvider.future);

      t.container.read(followedTagSetProvider.notifier).note('dart', following: true);
      expect(t.container.read(followsTagProvider('dart')), isTrue);

      t.container.read(followedTagSetProvider.notifier).note('dart', following: false);
      expect(t.container.read(followsTagProvider('dart')), isFalse);
    });

    test('nothing is known without a session', () async {
      final t = harness(signedIn: false);
      await t.container.read(followedTagSetProvider.future);
      expect(t.calls, isEmpty);
    });
  });

  test('one list failing does not blank the other', () async {
    // A blocks endpoint that errors must not make the follow buttons forget who you
    // follow — which is what a single try around both walks used to do.
    final t = harness(following: ['alice'], blocksFail: true);
    await t.container.read(relationshipsProvider.future);

    expect(t.container.read(followsProvider('alice')), isTrue);
    expect(t.container.read(blocksProvider('spammer')), isNull, reason: 'unknown, not false');
  });
}
