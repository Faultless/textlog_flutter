/// Every scrollable list of posts in this app is one of these sources.
///
/// Adding a feed means: add a case here, add its path in [pathOf] and its query in
/// [queryOf], and the notifier, pagination, error handling and UI come along
/// unchanged.
///
/// Value equality is required — these are Riverpod family keys, so two `TagFeed('dart')`
/// instances must resolve to the same cached provider.
library;

sealed class FeedSource {
  const FeedSource();
}

final class LatestFeed extends FeedSource {
  const LatestFeed();

  @override
  bool operator ==(Object other) => other is LatestFeed;

  @override
  int get hashCode => (LatestFeed).hashCode;
}

final class HotFeed extends FeedSource {
  const HotFeed();

  @override
  bool operator ==(Object other) => other is HotFeed;

  @override
  int get hashCode => (HotFeed).hashCode;
}

/// A profile's top-level posts. The server calls these "notes"; `users/{h}/posts` is
/// the deprecated alias for the same thing.
final class NotesFeed extends FeedSource {
  const NotesFeed(this.handle);

  final String handle;

  @override
  bool operator ==(Object other) => other is NotesFeed && other.handle == handle;

  @override
  int get hashCode => Object.hash(NotesFeed, handle);
}

/// A profile's replies, which the site shows on its own tab.
final class UserRepliesFeed extends FeedSource {
  const UserRepliesFeed(this.handle);

  final String handle;

  @override
  bool operator ==(Object other) => other is UserRepliesFeed && other.handle == handle;

  @override
  int get hashCode => Object.hash(UserRepliesFeed, handle);
}

final class TagFeed extends FeedSource {
  const TagFeed(this.tag);

  final String tag;

  @override
  bool operator ==(Object other) => other is TagFeed && other.tag == tag;

  @override
  int get hashCode => Object.hash(TagFeed, tag);
}

/// Replies to a post.
///
/// [depth] is the reason a thread costs one request instead of one per node: the
/// server walks the tree for us and returns the whole subtree flat, each post
/// carrying its own `depth` and `parent_id`.
final class RepliesFeed extends FeedSource {
  const RepliesFeed(this.postId, {this.depth = 1});

  final int postId;

  /// 1–20. One is the server's default and returns direct children only.
  final int depth;

  @override
  bool operator ==(Object other) =>
      other is RepliesFeed && other.postId == postId && other.depth == depth;

  @override
  int get hashCode => Object.hash(RepliesFeed, postId, depth);
}

/// Full-text search, server side. Its cursor is an offset rather than an id, which
/// the pagination code does not need to know.
final class SearchFeed extends FeedSource {
  const SearchFeed(this.query);

  final String query;

  @override
  bool operator ==(Object other) => other is SearchFeed && other.query == query;

  @override
  int get hashCode => Object.hash(SearchFeed, query);
}

/// Pure: source -> API path. No I/O, no Flutter, trivially unit tested.
String pathOf(FeedSource source) => switch (source) {
  LatestFeed() => 'feeds/latest',
  HotFeed() => 'feeds/hot',
  NotesFeed(:final handle) => 'users/${Uri.encodeComponent(handle)}/notes',
  UserRepliesFeed(:final handle) => 'users/${Uri.encodeComponent(handle)}/replies',
  TagFeed(:final tag) => 'tags/${Uri.encodeComponent(tag)}/posts',
  RepliesFeed(:final postId) => 'posts/$postId/replies',
  SearchFeed() => 'search',
};

/// Query parameters beyond `limit` and `cursor`.
Map<String, String> queryOf(FeedSource source) => switch (source) {
  RepliesFeed(:final depth) when depth > 1 => {'depth': '$depth'},
  SearchFeed(:final query) => {'q': query},
  _ => const {},
};

/// Which feeds are worth keeping on disk between sessions, and under what key.
///
/// Only the two the app can open on: `hot` and `latest`. A cold start shows one of
/// them, so having them already on screen is the whole win — whereas keeping every
/// tag page and every search anyone ever opened would fill a phone with feeds nobody
/// is about to look at.
///
/// The signed-in feeds are deliberately absent: `for you` and `to me` are activity,
/// and a stale copy of who replied to you is worse than an honest moment of loading.
String? coldStorageKeyOf(FeedSource source) => switch (source) {
  LatestFeed() => 'feed:latest',
  HotFeed() => 'feed:hot',
  _ => null,
};
