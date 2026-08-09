import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import '../core/models.dart';
import 'cache.dart';
import 'providers.dart';

final class FeedState {
  const FeedState({
    required this.posts,
    this.cursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<Post> posts;
  final String? cursor;
  final bool loadingMore;

  /// A failed *next page* must not discard the pages already on screen, so it
  /// lives here rather than turning the whole provider into an AsyncError.
  final Object? loadMoreError;

  bool get hasMore => cursor != null;

  FeedState copyWith({
    List<Post>? posts,
    String? cursor,
    bool? loadingMore,
    Object? loadMoreError,
  }) => FeedState(
    posts: posts ?? this.posts,
    cursor: cursor ?? this.cursor,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError,
  );
}

/// One notifier, every feed. `arg` is the source; the family key does the routing.
final feedProvider =
    AsyncNotifierProvider.autoDispose.family<FeedNotifier, FeedState, FeedSource>(
      FeedNotifier.new,
    );

/// Feeds currently on screen or still cached. Reading a family member that is not
/// alive would create it, and creating it would fetch, so a local change is pushed to
/// the ones that exist instead of guessing at names.
final _liveFeeds = <FeedNotifier>{};

/// Reflect an edit or a delete in every feed holding that post.
void applyToLiveFeeds(int postId, Post? updated) {
  for (final feed in _liveFeeds.toList()) {
    feed.applyLocal(postId, updated);
  }
}

class FeedNotifier extends AutoDisposeFamilyAsyncNotifier<FeedState, FeedSource> {
  @override
  Future<FeedState> build(FeedSource arg) async {
    cacheFor(ref, feedCacheDuration);
    _liveFeeds.add(this);
    ref.onDispose(() => _liveFeeds.remove(this));
    final page = await ref.watch(apiProvider).feed(arg);
    ref.read(postCacheProvider).remember(page.items);
    ref.read(repliesCacheProvider).noticeCounts(page.items);
    return FeedState(posts: page.items, cursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(apiProvider).feed(arg, cursor: current.cursor);
      ref.read(postCacheProvider).remember(page.items);
      ref.read(repliesCacheProvider).noticeCounts(page.items);
      state = AsyncData(
        FeedState(posts: [...current.posts, ...page.items], cursor: page.nextCursor),
      );
    } catch (error) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: error));
    }
  }

  /// Reflect a local edit or delete without refetching. The server already agreed,
  /// so showing the old copy until a refresh lands would just be wrong for longer.
  void applyLocal(int postId, Post? updated) {
    final current = state.valueOrNull;
    if (current == null) return;
    final index = current.posts.indexWhere((post) => post.id == postId);
    if (index < 0) return;

    final posts = [...current.posts];
    if (updated == null) {
      posts.removeAt(index);
    } else {
      posts[index] = updated;
    }
    state = AsyncData(current.copyWith(posts: posts));
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
