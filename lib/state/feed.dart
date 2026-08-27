import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import '../data/feed_store.dart';
import '../core/models.dart';
import 'cache.dart';
import 'rate_limit.dart';
import 'providers.dart';
import 'session.dart';

final class FeedState {
  const FeedState({
    required this.posts,
    this.cursor,
    this.hasUnread = false,
    this.unreadCount = 0,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<Post> posts;
  final String? cursor;

  /// Latest feed, signed in: whether anything is unread anywhere in it, and how
  /// much. Both come from the server; the app does not try to count for itself.
  final bool hasUnread;
  final int unreadCount;

  final bool loadingMore;

  /// A failed *next page* must not discard the pages already on screen, so it
  /// lives here rather than turning the whole provider into an AsyncError.
  final Object? loadMoreError;

  bool get hasMore => cursor != null;

  FeedState copyWith({
    List<Post>? posts,
    String? cursor,
    bool? hasUnread,
    int? unreadCount,
    bool? loadingMore,
    Object? loadMoreError,
  }) => FeedState(
    posts: posts ?? this.posts,
    cursor: cursor ?? this.cursor,
    hasUnread: hasUnread ?? this.hasUnread,
    unreadCount: unreadCount ?? this.unreadCount,
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

/// Whether the latest feed has anything unread, for the tab dot.
///
/// Its own provider so the tab row can watch one boolean instead of rebuilding on
/// every page the feed loads.
final latestUnreadProvider = Provider<bool>((ref) {
  return ref.watch(
    feedProvider(const LatestFeed()).select(
      (feed) => feed.valueOrNull?.hasUnread ?? false,
    ),
  );
});

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
    // Watch only whether anyone is signed in: that changes the answer a feed gives,
    // so it has to refetch. Watching the session itself would also refetch when the
    // confirmation behind a cold start fills in a bio, and watching the token would
    // dispose this build halfway through to do it.
    ref.watch(signedInProvider);
    // Then *read* the settled session for the token. Awaiting costs a microtask and
    // no request — the session never waits on the network to produce a value — and
    // without it the first feed read of a launch can go out anonymously and come
    // back carrying accounts the reader had blocked.
    final session = await ref.read(sessionProvider.future);
    final token = session?.token;
    final viewer = session?.account.handle;

    final key = coldStorageKeyOf(arg, viewer: viewer);
    if (key != null && _servedFromStore.add(key)) {
      if (await FeedStore.load(key) case final stored?) {
        try {
          final page = Page.fromJson(stored, Post.fromJson);
          if (page.items.isNotEmpty) {
            ref.read(postCacheProvider).remember(page.items);
            ref.read(repliesCacheProvider).noticeCounts(page.items);
            _revalidate(key, token);
            return FeedState(posts: page.items, cursor: page.nextCursor);
          }
        } catch (_) {
          // Stored by a version that shaped it differently. Fetch instead.
        }
      }
    }

    return _fetch(key, token);
  }

  /// Fetch the first page, keeping it for the next cold start.
  Future<FeedState> _fetch(String? key, String? token) async {
    final json = await ref.read(apiProvider).feedJson(arg, token: token);
    final page = Page.fromJson(json, Post.fromJson);
    ref.read(postCacheProvider).remember(page.items);
    ref.read(repliesCacheProvider).noticeCounts(page.items);
    if (key != null) await FeedStore.save(key, json);
    return FeedState(
      posts: page.items,
      cursor: page.nextCursor,
      hasUnread: page.hasUnread,
      unreadCount: page.unreadCount,
    );
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
  void _revalidate(String key, String? token) {
    Future<void>(() async {
      try {
        final fresh = await _fetch(key, token);
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
      final page = await ref.read(apiProvider).feed(
        arg,
        cursor: current.cursor,
        token: ref.read(viewerProvider)?.token,
      );
      ref.read(postCacheProvider).remember(page.items);
      ref.read(repliesCacheProvider).noticeCounts(page.items);
      state = AsyncData(
        FeedState(
          posts: [...current.posts, ...page.items],
          cursor: page.nextCursor,
          hasUnread: page.hasUnread,
          unreadCount: page.unreadCount,
        ),
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

  /// Mark [postIds] read, and say so on screen before the server has answered.
  ///
  /// The server takes 100 an request, so this chunks. A failure is swallowed on
  /// purpose: the reader has already moved on, and a dot reappearing under them
  /// would be a worse outcome than one that is briefly optimistic.
  Future<void> markRead(Iterable<int> postIds) async {
    final token = ref.read(viewerProvider)?.token;
    final current = state.valueOrNull;
    if (token == null || current == null) return;

    final wanted = postIds
        .where((id) => current.posts.any((post) => post.id == id && post.unread == true))
        .toSet()
        .toList();
    if (wanted.isEmpty) return;

    state = AsyncData(current.copyWith(
      posts: [
        for (final post in current.posts)
          wanted.contains(post.id) ? post.copyWith(read: true) : post,
      ],
      unreadCount: (current.unreadCount - wanted.length).clamp(0, current.unreadCount),
    ));

    try {
      for (var start = 0; start < wanted.length; start += 100) {
        await ref
            .read(apiProvider)
            .markLatestRead(token, wanted.skip(start).take(100).toList());
      }
    } catch (_) {
      // Left as read locally. The next fetch settles it either way.
    }
  }

  /// Everything, including the pages not loaded — which is why it is the server's
  /// `read-all` rather than a walk over what is on screen.
  Future<void> markAllRead() async {
    final token = ref.read(viewerProvider)?.token;
    final current = state.valueOrNull;
    if (token == null || current == null) return;

    state = AsyncData(current.copyWith(
      posts: [for (final post in current.posts) post.copyWith(read: true)],
      hasUnread: false,
      unreadCount: 0,
    ));
    try {
      await ref.read(apiProvider).markLatestReadAll(token);
    } catch (_) {
      // Same reasoning as markRead.
    }
  }
}
