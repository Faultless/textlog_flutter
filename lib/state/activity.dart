import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../data/api.dart';
import 'cache.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'read_queue.dart';
import 'session.dart';

final class ActivityState {
  const ActivityState({
    required this.items,
    this.cursor,
    this.hasUnread = false,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<Activity> items;
  final String? cursor;

  /// Whether anything unread remains *anywhere* in the feed, which the server tells
  /// us per page. Cheaper than counting, and it is what the tab marker needs.
  final bool hasUnread;

  final bool loadingMore;

  /// A failed next page must not discard the pages already on screen.
  final Object? loadMoreError;

  bool get hasMore => cursor != null;

  ActivityState copyWith({
    List<Activity>? items,
    String? cursor,
    bool? hasUnread,
    bool? loadingMore,
    Object? loadMoreError,
  }) => ActivityState(
    items: items ?? this.items,
    cursor: cursor ?? this.cursor,
    hasUnread: hasUnread ?? this.hasUnread,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError,
  );
}

/// `/activities/for-you` and `/activities/to-me`.
///
/// Both need a token, so both are empty without one rather than erroring — the tabs
/// they belong to are not offered when signed out.
final activityProvider =
    AsyncNotifierProvider.autoDispose
        .family<ActivityNotifier, ActivityState, ActivityScope>(ActivityNotifier.new);

/// Just the marker, so the tab bar can watch it without rebuilding on every page.
final activityUnreadProvider = Provider.autoDispose.family<bool, ActivityScope>(
  (ref, scope) => ref.watch(activityProvider(scope)).valueOrNull?.hasUnread ?? false,
);

class ActivityNotifier
    extends AutoDisposeFamilyAsyncNotifier<ActivityState, ActivityScope> {
  /// Held for the queue, which may flush after this notifier is gone.
  TextlogApi? _api;
  String? _token;
  late final _queue = ReadQueue<String>(_flush);

  @override
  Future<ActivityState> build(ActivityScope arg) async {
    cacheFor(ref, feedCacheDuration);
    _api = ref.read(apiProvider);
    ref.onDispose(_queue.flush);
    // Await the session rather than reading whatever it holds right now. On a cold
    // start it is still loading, and treating that as "not signed in" would show an
    // empty feed for a moment and then rebuild — which also meant this provider was
    // torn down mid-flight the first time round.
    final token = (await ref.watch(sessionProvider.future))?.token;
    if (token == null) return const ActivityState(items: []);

    final page = await ref.watch(apiProvider).activities(token, arg);
    _remember(page.items);
    return ActivityState(
      items: page.items,
      cursor: page.nextCursor,
      hasUnread: page.hasUnread,
    );
  }

  /// Activity rows carry whole posts. Putting them in the shared cache means tapping
  /// one into its thread costs nothing.
  void _remember(List<Activity> items) {
    final posts = [for (final item in items) ?item.post];
    if (posts.isEmpty) return;
    ref.read(postCacheProvider).remember(posts);
    ref.read(repliesCacheProvider).noticeCounts(posts);
  }

  Future<void> loadMore({bool asked = false}) async {
    final current = state.valueOrNull;
    final token = ref.read(sessionProvider).valueOrNull?.token;
    if (current == null || token == null || !current.hasMore || current.loadingMore) return;

    if (!asked) {
      // The scroll listener fires on every frame near the bottom.
      if (current.loadMoreError != null) return;
      if (ref.read(rateLimitProvider).isTripped(ref.read(nowProvider)())) return;
    }

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref
          .read(apiProvider)
          .activities(token, arg, cursor: current.cursor);
      _remember(page.items);
      state = AsyncData(
        ActivityState(
          items: [...current.items, ...page.items],
          cursor: page.nextCursor,
          hasUnread: page.hasUnread,
        ),
      );
    } catch (error) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: error));
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// One batch, chunked to the hundred the server takes. A failure is swallowed —
  /// a dot reappearing under a moving thumb is worse.
  Future<void> _flush(List<String> ids) async {
    final token = _token;
    final api = _api;
    if (token == null || api == null) return;
    try {
      for (var start = 0; start < ids.length; start += 100) {
        await api.markRead(token, arg, ids.skip(start).take(100).toList());
      }
    } catch (_) {
      // Read locally. The next fetch settles it either way.
    }
  }

  /// Mark rows read: on screen now, on the server once the scrolling stops.
  Future<void> markRead(Iterable<String> ids) async {
    final current = state.valueOrNull;
    final token = ref.read(sessionProvider).valueOrNull?.token;
    if (current == null || token == null) return;
    _token = token;

    final unread = ids.where((id) => current.items.any((item) => item.id == id && item.unread));
    final wanted = unread.toSet().toList();
    if (wanted.isEmpty) return;

    state = AsyncData(current.copyWith(items: _read(current.items, wanted.toSet())));
    _queue.add(wanted);
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    final token = ref.read(sessionProvider).valueOrNull?.token;
    if (current == null || token == null) return;

    // Superseded: read-all covers every id that was waiting.
    _queue.clear();
    state = AsyncData(
      current.copyWith(
        items: _read(current.items, {for (final item in current.items) item.id}),
        hasUnread: false,
      ),
    );
    try {
      await ref.read(apiProvider).markAllRead(token, arg);
    } catch (_) {
      final now = state.valueOrNull;
      if (now != null) {
        state = AsyncData(now.copyWith(items: current.items, hasUnread: current.hasUnread));
      }
    }
  }

  List<Activity> _read(List<Activity> items, Set<String> ids) => [
    for (final item in items) if (ids.contains(item.id)) item.read() else item,
  ];
}
