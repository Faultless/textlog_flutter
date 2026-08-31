import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import '../core/unread.dart';
import '../data/api.dart';
import '../data/feed_store.dart';
import '../core/models.dart';
import 'cache.dart';
import 'rate_limit.dart';
import 'providers.dart';
import 'read_queue.dart';
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

  /// [hasUnread] is the server's, covering pages not loaded. [unreadCount] is the
  /// app's: what is left of the catch-up set. See `core/unread.dart`.
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

  /// Held for the queue, which may flush after this notifier is gone.
  TextlogApi? _api;
  String? _token;
  late final _queue = ReadQueue<int>(_flush);

  /// What is left of the catch-up set. A first page sets it, later pages spend it.
  var _budget = unreadCatchUp;

  /// Marked read this session, re-applied to later pages so a refresh cannot put a
  /// rail back.
  final _read = <int>{};

  @override
  Future<FeedState> build(FeedSource arg) async {
    cacheFor(ref, feedCacheDuration);
    _liveFeeds.add(this);
    ref.onDispose(() {
      _disposed = true;
      _liveFeeds.remove(this);
      _queue.flush();
    });
    _api = ref.read(apiProvider);

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
            final catchUp = _catchUp(page.items, first: true);
            return FeedState(
              posts: catchUp.posts,
              cursor: page.nextCursor,
              unreadCount: catchUp.unread,
            );
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
    final catchUp = _catchUp(page.items, first: true);
    return FeedState(
      posts: catchUp.posts,
      cursor: page.nextCursor,
      hasUnread: page.hasUnread,
      // Not the server's count: it counts everything back to the last visit, and
      // this reader is only being offered the newest few of them.
      unreadCount: catchUp.unread,
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
      final catchUp = _catchUp(page.items, first: false);
      state = AsyncData(
        FeedState(
          posts: [...current.posts, ...catchUp.posts],
          cursor: page.nextCursor,
          hasUnread: page.hasUnread,
          unreadCount: current.unreadCount + catchUp.unread,
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

  /// A page as this reader should see it. [first] resets the budget.
  ({List<Post> posts, int unread}) _catchUp(List<Post> items, {required bool first}) {
    final posts = _read.isEmpty
        ? items
        : [
            for (final post in items)
              _read.contains(post.id) ? post.copyWith(read: true) : post,
          ];
    final capped = capUnread(posts, budget: first ? unreadCatchUp : _budget);
    _budget = first ? unreadCatchUp - capped.unread : _budget - capped.unread;
    return capped;
  }

  /// One batch, chunked to the hundred the server takes. A failure is swallowed —
  /// a rail reappearing under a moving thumb is worse.
  Future<void> _flush(List<int> ids) async {
    final token = _token;
    final api = _api;
    if (token == null || api == null) return;
    try {
      for (var start = 0; start < ids.length; start += 100) {
        await api.markLatestRead(token, ids.skip(start).take(100).toList());
      }
    } catch (_) {
      // Left as read locally. The next fetch settles it either way.
    }
  }

  /// Mark [postIds] read: on screen now, on the server once the scrolling stops.
  ///
  /// Reading the last of the catch-up set marks the whole feed read, pages that were
  /// never loaded included.
  Future<void> markRead(Iterable<int> postIds) async {
    final token = ref.read(viewerProvider)?.token;
    final current = state.valueOrNull;
    if (token == null || current == null) return;
    _token = token;

    final wanted = {...postIds}
        .where((id) => current.posts.any((post) => post.id == id && post.unread == true))
        .toList();
    if (wanted.isEmpty) return;

    _read.addAll(wanted);
    final posts = [
      for (final post in current.posts)
        wanted.contains(post.id) ? post.copyWith(read: true) : post,
    ];
    final left = posts.where((post) => post.unread == true).length;
    state = AsyncData(current.copyWith(posts: posts, unreadCount: left));

    if (left == 0 && current.hasUnread) return markAllRead();
    _queue.add(wanted);
  }

  /// Everything, including the pages not loaded — which is why it is the server's
  /// `read-all` rather than a walk over what is on screen.
  Future<void> markAllRead() async {
    final token = ref.read(viewerProvider)?.token;
    final current = state.valueOrNull;
    if (token == null || current == null) return;

    // Superseded: read-all covers every id that was waiting.
    _queue.clear();
    _read.addAll([for (final post in current.posts) post.id]);
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
