import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import '../data/feed_store.dart';
import '../core/models.dart';
import 'cache.dart';
import 'rate_limit.dart';
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

/// Storage keys already served from disk this session.
///
/// A stored page is for a *cold start*, so it is offered once. Every later build —
/// a pull to refresh, the invalidation that follows posting — has to reach the
/// server, or the reader would be shown the page from before their own write.
final _servedFromStore = <String>{};

class FeedNotifier extends AutoDisposeFamilyAsyncNotifier<FeedState, FeedSource> {
  var _disposed = false;

  @override
  Future<FeedState> build(FeedSource arg) async {
    cacheFor(ref, feedCacheDuration);
    _liveFeeds.add(this);
    ref.onDispose(() {
      _disposed = true;
      _liveFeeds.remove(this);
    });

    // A feed kept from a previous session goes up first, and the network lands
    // behind it. Only the feeds a cold start can open on are stored — see
    // coldStorageKeyOf.
    final key = coldStorageKeyOf(arg);
    if (key != null && _servedFromStore.add(key)) {
      if (await FeedStore.load(key) case final stored?) {
        try {
          final page = Page.fromJson(stored, Post.fromJson);
          if (page.items.isNotEmpty) {
            ref.read(postCacheProvider).remember(page.items);
            ref.read(repliesCacheProvider).noticeCounts(page.items);
            _revalidate(key);
            return FeedState(posts: page.items, cursor: page.nextCursor);
          }
        } catch (_) {
          // Stored by a version that shaped it differently. Fetch instead.
        }
      }
    }

    return _fetch(key);
  }

  /// Fetch the first page, keeping it for the next cold start.
  Future<FeedState> _fetch(String? key) async {
    final json = await ref.watch(apiProvider).feedJson(arg);
    final page = Page.fromJson(json, Post.fromJson);
    ref.read(postCacheProvider).remember(page.items);
    ref.read(repliesCacheProvider).noticeCounts(page.items);
    if (key != null) await FeedStore.save(key, json);
    return FeedState(posts: page.items, cursor: page.nextCursor);
  }

  /// Replace the stored page with a fresh one, without the reader waiting on it.
  ///
  /// In place rather than through [refresh]: `refresh` invalidates, which builds a
  /// new notifier, which would read the same stored page and revalidate again —
  /// forever. Writing `state` directly ends there.
  ///
  /// Not awaited by [build] either. The stored posts are already on screen, and a
  /// failure here leaves them there, which is the right outcome: yesterday's posts
  /// beat an error page over a feed that loaded fine yesterday.
  void _revalidate(String key) {
    Future<void>(() async {
      try {
        final fresh = await _fetch(key);
        if (_disposed) return;
        state = AsyncData(fresh);
      } catch (_) {
        // Offline. The stored page stands.
      }
    });
  }

  /// [asked] means the reader tapped retry, the one case that ignores both the
  /// last error and a tripped limit.
  Future<void> loadMore({bool asked = false}) async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;

    if (!asked) {
      // The scroll listener fires on every frame near the bottom.
      if (current.loadMoreError != null) return;
      if (ref.read(rateLimitProvider).isTripped(ref.read(nowProvider)())) return;
    }

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

  /// For tests and for signing out: forget that a cold start has been served, so the
  /// next build offers the stored page again.
  static void forgetColdStarts() => _servedFromStore.clear();
}
