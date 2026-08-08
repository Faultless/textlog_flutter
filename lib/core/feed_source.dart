/// Every scrollable list of posts in this app is one of these five sources.
///
/// Adding a sixth feed means: add a case here, add its path in [pathOf], and the
/// notifier, pagination, error handling and UI come along unchanged.
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

final class UserFeed extends FeedSource {
  const UserFeed(this.handle);

  final String handle;

  @override
  bool operator ==(Object other) => other is UserFeed && other.handle == handle;

  @override
  int get hashCode => Object.hash(UserFeed, handle);
}

final class TagFeed extends FeedSource {
  const TagFeed(this.tag);

  final String tag;

  @override
  bool operator ==(Object other) => other is TagFeed && other.tag == tag;

  @override
  int get hashCode => Object.hash(TagFeed, tag);
}

final class RepliesFeed extends FeedSource {
  const RepliesFeed(this.postId);

  final int postId;

  @override
  bool operator ==(Object other) => other is RepliesFeed && other.postId == postId;

  @override
  int get hashCode => Object.hash(RepliesFeed, postId);
}

/// Pure: source -> API path. No I/O, no Flutter, trivially unit tested.
String pathOf(FeedSource source) => switch (source) {
  LatestFeed() => 'feeds/latest',
  HotFeed() => 'feeds/hot',
  UserFeed(:final handle) => 'users/${Uri.encodeComponent(handle)}/posts',
  TagFeed(:final tag) => 'tags/${Uri.encodeComponent(tag)}/posts',
  RepliesFeed(:final postId) => 'posts/$postId/replies',
};
