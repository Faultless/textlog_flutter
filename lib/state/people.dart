import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../data/api.dart';
import 'cache.dart';
import 'providers.dart';
import 'rate_limit.dart';
import 'session.dart';

/// Which list of accounts or tags a screen is showing.
///
/// Value equality, because these are Riverpod family keys.
final class PeopleSource {
  const PeopleSource.followers(this.handle) : kind = PeopleKind.followers, tag = null;
  const PeopleSource.following(this.handle) : kind = PeopleKind.following, tag = null;
  const PeopleSource.blocks(this.handle) : kind = PeopleKind.blocks, tag = null;
  const PeopleSource.tagFollowers(this.tag) : kind = PeopleKind.followers, handle = null;

  final PeopleKind kind;
  final String? handle;
  final String? tag;

  @override
  bool operator ==(Object other) =>
      other is PeopleSource &&
      other.kind == kind &&
      other.handle == handle &&
      other.tag == tag;

  @override
  int get hashCode => Object.hash(kind, handle, tag);
}

final class PeopleState<T> {
  const PeopleState({
    required this.items,
    this.cursor,
    this.loadingMore = false,
    this.loadMoreError,
  });

  final List<T> items;
  final String? cursor;
  final bool loadingMore;
  final Object? loadMoreError;

  bool get hasMore => cursor != null;

  PeopleState<T> copyWith({
    List<T>? items,
    String? cursor,
    bool? loadingMore,
    Object? loadMoreError,
  }) => PeopleState(
    items: items ?? this.items,
    cursor: cursor ?? this.cursor,
    loadingMore: loadingMore ?? this.loadingMore,
    loadMoreError: loadMoreError,
  );
}

/// Followers, following and blocks — one notifier, keyed by which.
final peopleProvider =
    AsyncNotifierProvider.autoDispose
        .family<PeopleNotifier, PeopleState<UserRef>, PeopleSource>(PeopleNotifier.new);

class PeopleNotifier
    extends AutoDisposeFamilyAsyncNotifier<PeopleState<UserRef>, PeopleSource> {
  @override
  Future<PeopleState<UserRef>> build(PeopleSource arg) async {
    cacheFor(ref, feedCacheDuration);
    final page = await _page(null);
    return PeopleState(items: page.items, cursor: page.nextCursor);
  }

  Future<Page<UserRef>> _page(String? cursor) {
    final api = ref.read(apiProvider);
    // Only the block list is private, but the token costs nothing to send.
    final token = ref.read(sessionProvider).valueOrNull?.token;
    final tag = arg.tag;
    return tag != null
        ? api.tagFollowers(tag, cursor: cursor)
        : api.people(arg.handle!, arg.kind, cursor: cursor, token: token);
  }

  Future<void> loadMore({bool asked = false}) async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    if (!asked) {
      if (current.loadMoreError != null) return;
      if (ref.read(rateLimitProvider).isTripped(ref.read(nowProvider)())) return;
    }

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await _page(current.cursor);
      state = AsyncData(
        PeopleState(items: [...current.items, ...page.items], cursor: page.nextCursor),
      );
    } catch (error) {
      state = AsyncData(current.copyWith(loadingMore: false, loadMoreError: error));
    }
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }

  /// Drop an account from the list without refetching, for unblocking in place.
  void removeLocal(String handle) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(
      current.copyWith(
        items: current.items.where((person) => person.handle != handle).toList(),
      ),
    );
  }
}

/// The hashtags an account follows.
final followedTagsProvider =
    AsyncNotifierProvider.autoDispose
        .family<FollowedTagsNotifier, PeopleState<TagDetails>, String>(
          FollowedTagsNotifier.new,
        );

class FollowedTagsNotifier
    extends AutoDisposeFamilyAsyncNotifier<PeopleState<TagDetails>, String> {
  @override
  Future<PeopleState<TagDetails>> build(String arg) async {
    cacheFor(ref, feedCacheDuration);
    final page = await ref.watch(apiProvider).followedTags(arg);
    return PeopleState(items: page.items, cursor: page.nextCursor);
  }

  Future<void> loadMore({bool asked = false}) async {
    final current = state.valueOrNull;
    if (current == null || !current.hasMore || current.loadingMore) return;
    if (!asked && current.loadMoreError != null) return;

    state = AsyncData(current.copyWith(loadingMore: true));
    try {
      final page = await ref.read(apiProvider).followedTags(arg, cursor: current.cursor);
      state = AsyncData(
        PeopleState(items: [...current.items, ...page.items], cursor: page.nextCursor),
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
