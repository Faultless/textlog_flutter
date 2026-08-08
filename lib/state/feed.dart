import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import '../core/models.dart';
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

class FeedNotifier extends AutoDisposeFamilyAsyncNotifier<FeedState, FeedSource> {
  @override
  Future<FeedState> build(FeedSource arg) async {
    final page = await ref.watch(apiProvider).feed(arg);
    return FeedState(posts: page.items, cursor: page.nextCursor);
  }

  Future<void> loadMore() async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(apiProvider).feed(arg, cursor: current.cursor);
      state = AsyncData(
        FeedState(posts: [...current.posts, ...page.items], cursor: page.nextCursor),
      );
    } catch (error) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: error));
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
