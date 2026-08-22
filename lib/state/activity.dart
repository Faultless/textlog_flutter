import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../data/api.dart';
import 'cache.dart';
import 'providers.dart';
import 'rate_limit.dart';
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
  @override
  Future<ActivityState> build(ActivityScope arg) async {
    cacheFor(ref, feedCacheDuration);
    final token = ref.watch(sessionProvider).valueOrNull?.token;
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

  /// Mark rows read, on screen first and on the server after.
  ///
  /// Reading is not a thing to wait for: the row should stop being highlighted the
  /// instant you open it. If the request fails the highlight comes back, which is
  /// the honest outcome — the server still thinks it is unread.
  Future<void> markRead(Iterable<String> ids) async {
    final current = state.valueOrNull;
    final token = ref.read(sessionProvider).valueOrNull?.token;
    if (current == null || token == null) return;

    final unread = ids.where((id) => current.items.any((item) => item.id == id && item.unread));
    final wanted = unread.toSet().toList();
    if (wanted.isEmpty) return;

    state = AsyncData(current.copyWith(items: _read(current.items, wanted.toSet())));
    try {
      // The server takes a hundred at a time.
      for (var start = 0; start < wanted.length; start += 100) {
        await ref
            .read(apiProvider)
            .markRead(token, arg, wanted.skip(start).take(100).toList());
      }
    } catch (_) {
      final now = state.valueOrNull;
      if (now != null) state = AsyncData(now.copyWith(items: current.items));
    }
  }

  Future<void> markAllRead() async {
    final current = state.valueOrNull;
    final token = ref.read(sessionProvider).valueOrNull?.token;
    if (current == null || token == null) return;

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
