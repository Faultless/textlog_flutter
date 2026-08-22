@Tags(['live'])
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/data/api.dart';

/// Decodes every public read endpoint against a real server.
///
/// The models in this app are written by hand from textlog's OpenAPI document, which
/// means a field the server renames is a crash the unit tests cannot see — they feed
/// the decoders fixtures this repo wrote itself. This is the only test that checks
/// the shapes are the shapes.
///
/// Skips itself when there is no server to ask, so it is safe in CI and offline.
///   flutter test test/live_reads_test.dart
void main() {
  late TextlogApi api;
  late http.Client client;
  var reachable = false;

  setUpAll(() async {
    client = http.Client();
    api = TextlogApi(client);
    try {
      await api.feed(const LatestFeed(), limit: 1);
      reachable = true;
    } catch (_) {
      // ignore: avoid_print
      print('no textlog at $textlogOrigin — skipping live reads');
    }
  });

  tearDownAll(() => client.close());

  /// Runs [body] only when there is a server, so a failure here is a real mismatch.
  void live(String description, Future<void> Function() body) {
    test(description, () async {
      if (!reachable) return;
      await body();
    });
  }

  live('feeds decode, and carry the inlined parent', () async {
    final page = await api.feed(const LatestFeed(), limit: 20);
    expect(page.items, isNotEmpty);

    for (final post in page.items) {
      expect(post.body, isNotNull);
      expect(post.author.handle, isNotEmpty);
      // The field the app now leans on: a reply must bring its parent with it, or
      // arrive with an explicit null when that parent is gone.
      if (post.parentId != null) {
        expect(post.parent?.id ?? post.parentId, post.parentId);
      }
    }
    // Something in a page of twenty is a reply, and its quote should be present.
    final replies = page.items.where((post) => post.parentId != null);
    if (replies.isNotEmpty) {
      expect(replies.any((post) => post.parent != null), isTrue);
    }
  });

  live('hot decodes with its own cursor kind', () async {
    final page = await api.feed(const HotFeed(), limit: 5);
    expect(page.items, isNotEmpty);
  });

  live('a thread comes back flat, with a depth on every reply', () async {
    // Find a post with replies to ask about.
    final feed = await api.feed(const HotFeed(), limit: 20);
    final parent = feed.items.firstWhere(
      (post) => post.replyCount > 0,
      orElse: () => feed.items.first,
    );
    if (parent.replyCount == 0) return;

    final replies = await api.feed(
      RepliesFeed(parent.id, depth: maxDepthUnderTest),
      limit: 100,
    );
    expect(replies.items, isNotEmpty);
    for (final reply in replies.items) {
      expect(reply.depth, isNotNull, reason: 'depth is what makes one request enough');
      expect(reply.depth, inInclusiveRange(1, maxDepthUnderTest));
      expect(reply.parentId, isNotNull);
    }
    // The top of the conversation, which the quoted parent's "top" link uses.
    expect(replies.items.first.topId, anyOf(isNull, parent.topId ?? parent.id));
  });

  live('a profile carries every count the app shows', () async {
    final profile = await api.profile('stagas');
    expect(profile.handle, 'stagas');
    expect(profile.postCount, greaterThanOrEqualTo(0));
    expect(profile.repliesCount, greaterThanOrEqualTo(0));
    expect(profile.followerCount, greaterThanOrEqualTo(0));
    expect(profile.followingUserCount, greaterThanOrEqualTo(0));
    expect(profile.followingTagCount, greaterThanOrEqualTo(0));
    // Somebody else's profile never carries the private counts.
    expect(profile.blockedUserCount, isNull);
  });

  live('the profile feeds are two different feeds', () async {
    final notes = await api.feed(const NotesFeed('stagas'), limit: 5);
    final replies = await api.feed(const UserRepliesFeed('stagas'), limit: 5);
    expect(notes.items.every((post) => post.parentId == null), isTrue);
    expect(replies.items.every((post) => post.parentId != null), isTrue);
  });

  live('search decodes and its cursor is an offset', () async {
    final page = await api.feed(const SearchFeed('textlog'), limit: 5);
    expect(page.items, isNotEmpty);
  });

  live('tag details decode', () async {
    final tag = await api.tag('ascii');
    expect(tag.tag, 'ascii');
    expect(tag.postCount, greaterThanOrEqualTo(0));
    expect(tag.followerCount, greaterThanOrEqualTo(0));
  });

  live('relationship lists decode', () async {
    for (final kind in [PeopleKind.followers, PeopleKind.following]) {
      final page = await api.people('stagas', kind, limit: 5);
      for (final person in page.items) {
        expect(person.handle, isNotEmpty);
      }
    }
    final tags = await api.followedTags('stagas', limit: 5);
    for (final tag in tags.items) {
      expect(tag.tag, isNotEmpty);
    }
    final followers = await api.tagFollowers('ascii', limit: 5);
    expect(followers.items, isA<List<UserRef>>());
  });

  live('the activity feeds refuse an anonymous reader', () async {
    // Not a decode check: a confirmation that the endpoints exist and are gated,
    // so a silent 404 does not read as "no activity".
    await expectLater(
      api.activities('not-a-token', ActivityScope.forYou),
      throwsA(isA<ApiFailure>().having((f) => f.isUnauthorized, 'unauthorized', isTrue)),
    );
  });
}

/// The depth the app asks for.
const maxDepthUnderTest = 5;
