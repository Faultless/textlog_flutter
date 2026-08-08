import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/body_tokens.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/sse.dart';

void main() {
  group('tokenizeBody', () {
    test('splits mentions, hashtags and links out of plain text', () {
      final tokens = tokenizeBody('hey @stagas see #open_source at https://textlog.cc ok');
      expect(tokens.whereType<MentionToken>().single.handle, 'stagas');
      expect(tokens.whereType<TagToken>().single.tag, 'open_source');
      expect(tokens.whereType<LinkToken>().single.url, 'https://textlog.cc');
    });

    test('leaves sentence punctuation outside the link', () {
      final tokens = tokenizeBody('read https://textlog.cc/api.');
      expect(tokens.whereType<LinkToken>().single.url, 'https://textlog.cc/api');
      expect((tokens.last as PlainText).text, '.');
    });

    test('does not treat an email local part as a mention', () {
      final tokens = tokenizeBody('mail me at hi@example.com');
      expect(tokens.whereType<MentionToken>(), isEmpty);
    });

    test('round-trips a body with no tokens', () {
      final tokens = tokenizeBody('just words');
      expect((tokens.single as PlainText).text, 'just words');
    });
  });

  group('relativeTime', () {
    final now = DateTime(2026, 8, 8, 12);

    test('matches the server ladder', () {
      expect(relativeTime(now.subtract(const Duration(seconds: 5)), now: now), '5s');
      expect(relativeTime(now.subtract(const Duration(minutes: 3)), now: now), '3m');
      expect(relativeTime(now.subtract(const Duration(hours: 5)), now: now), '5h');
      expect(relativeTime(now.subtract(const Duration(days: 4)), now: now), '4d');
      expect(relativeTime(now.subtract(const Duration(days: 90)), now: now), '3mo');
      expect(relativeTime(now.subtract(const Duration(days: 800)), now: now), '2y');
    });

    test('never shows less than one second', () {
      expect(relativeTime(now, now: now), '1s');
    });
  });

  group('pathOf', () {
    test('maps every source to its documented endpoint', () {
      expect(pathOf(const LatestFeed()), 'feeds/latest');
      expect(pathOf(const HotFeed()), 'feeds/hot');
      expect(pathOf(const UserFeed('stagas')), 'users/stagas/posts');
      expect(pathOf(const TagFeed('open_source')), 'tags/open_source/posts');
      expect(pathOf(const RepliesFeed(274)), 'posts/274/replies');
    });
  });

  group('FeedSource equality', () {
    test('same source is the same Riverpod family key', () {
      expect(const TagFeed('dart'), const TagFeed('dart'));
      expect(const TagFeed('dart').hashCode, const TagFeed('dart').hashCode);
      expect(const TagFeed('dart'), isNot(const TagFeed('flutter')));
      expect(const LatestFeed(), isNot(const HotFeed()));
    });
  });

  group('sseDataOf', () {
    test('yields data for the named event only', () async {
      final lines = Stream.fromIterable([
        'event: ready',
        'data: {"status":"connected"}',
        '',
        ': heartbeat',
        '',
        'id: 1',
        'event: post',
        'data: {"id":1}',
        '',
      ]);
      expect(await sseDataOf(lines, 'post').toList(), ['{"id":1}']);
    });

    test('joins multi-line data payloads', () async {
      final lines = Stream.fromIterable(['event: post', 'data: a', 'data: b', '']);
      expect(await sseDataOf(lines, 'post').toList(), ['a\nb']);
    });
  });
}
