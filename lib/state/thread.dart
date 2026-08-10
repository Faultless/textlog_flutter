import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import '../core/models.dart';
import '../core/reply_tree.dart';
import 'cache.dart';
import 'providers.dart';
import 'rate_limit.dart';

// Lived here first; kept exported so importers do not care that it moved.
export 'cache.dart' show nowProvider;

/// How many levels to nest before a branch becomes a "N more replies" link.
const maxThreadDepth = 5;

/// Ceiling on network requests for one pass. Cached nodes are free.
const maxThreadRequests = 8;

/// How many of those may be in flight together.
const maxThreadConcurrency = 2;

/// How a pass over the thread treats what is already cached.
enum ThreadFetch {
  /// Normal open: reuse anything cached, fetch only what is missing.
  cached,

  /// Background pass: refetch what has aged past [repliesTtl], keep the rest.
  revalidate,

  /// The reader explicitly asked. Refetch everything, TTL be damned — this is the
  /// one path where "nothing happened" is the wrong answer.
  force,
}

final threadProvider =
    AsyncNotifierProvider.autoDispose.family<ThreadNotifier, List<ReplyNode>, int>(
      ThreadNotifier.new,
    );

class ThreadNotifier extends AutoDisposeFamilyAsyncNotifier<List<ReplyNode>, int> {
  var _disposed = false;

  @override
  Future<List<ReplyNode>> build(int arg) async {
    cacheFor(ref, postCacheDuration);
    _disposed = false;
    ref.onDispose(() => _disposed = true);

    final tree = await _walk(ThreadFetch.cached);

    // Everything came from cache and some of it has aged out. Show it now — it is
    // almost certainly still correct — and quietly bring it up to date behind the
    // reader rather than making them wait on a spinner.
    if (_hasStaleEntries()) {
      Future<void>.microtask(() async {
        if (_disposed) return;
        final fresh = await _walk(ThreadFetch.revalidate);
        // The reader may have left while that was in flight.
        if (!_disposed) state = AsyncData(fresh);
      });
    }

    return tree;
  }

  /// Pull-to-refresh. Refetches the whole tree: someone who pulls has usually just
  /// been told there is a new reply and wants to see it now.
  Future<void> refresh() async {
    final fresh = await _walk(ThreadFetch.force);
    state = AsyncData(fresh);
  }

  bool _hasStaleEntries() {
    final now = ref.read(nowProvider)();
    // Refreshing behind the reader is a courtesy, not worth the allowance.
    if (ref.read(rateLimitProvider).isTripped(now)) return false;

    final cache = ref.read(repliesCacheProvider);
    return _visited.any((id) => cache[id]?.isStale(now) ?? false);
  }

  /// Ids this notifier has walked, so revalidation knows the shape without refetching.
  final _visited = <int>{};

  /// Branches we may fetch: the thread itself, plus whatever the reader opened.
  /// Opening a thread is one request; each branch is one more, on demand.
  late final _expanded = <int>{arg};

  bool isExpanded(int id) => _expanded.contains(id);

  /// One request. Everything already loaded is reused.
  Future<void> expand(int id) async {
    if (!_expanded.add(id)) return;
    state = AsyncData(await _walk(ThreadFetch.cached));
  }

  Future<List<ReplyNode>> _walk(ThreadFetch mode) async {
    final loaded = <int, List<Post>>{};
    _visited.clear();

    var frontier = [arg];
    var budget = maxThreadRequests;

    for (var depth = 0; depth < maxThreadDepth && frontier.isNotEmpty; depth++) {
      final results = await _fetchLevel(frontier, mode, () => budget--);

      final next = <int>[];
      for (final (index, replies) in results.indexed) {
        if (replies == null) continue; // budget ran out; the branch stays "N more"
        final id = frontier[index];
        loaded[id] = replies;
        _visited.add(id);
        next.addAll(
          replies
              .where((post) => post.replyCount > 0 && _expanded.contains(post.id))
              .map((post) => post.id),
        );
      }
      frontier = next;
    }

    return assembleReplies(arg, loaded, maxDepth: maxThreadDepth);
  }

  /// A level, a few at a time. Cached nodes resolve immediately.
  Future<List<List<Post>?>> _fetchLevel(
    List<int> frontier,
    ThreadFetch mode,
    int Function() budget,
  ) async {
    final results = <List<Post>?>[];
    for (var start = 0; start < frontier.length; start += maxThreadConcurrency) {
      final slice = frontier.skip(start).take(maxThreadConcurrency);
      results.addAll(
        await Future.wait([for (final id in slice) _replies(id, mode: mode, budget: budget)]),
      );
    }
    return results;
  }

  /// Returns null when the request budget is spent, so the caller can leave that
  /// branch advertised-but-unloaded instead of dropping it.
  Future<List<Post>?> _replies(
    int id, {
    required ThreadFetch mode,
    required int Function() budget,
  }) async {
    final cache = ref.read(repliesCacheProvider);
    final now = ref.read(nowProvider)();
    final hit = cache[id];

    // A reused node costs nothing and does not touch the budget.
    final reuse = switch (mode) {
      ThreadFetch.cached => hit != null,
      ThreadFetch.revalidate => hit != null && !hit.isStale(now),
      ThreadFetch.force => false,
    };
    if (reuse) return hit!.posts;

    if (budget() <= 0) return hit?.posts;

    final replies = await cache.fetchOnce(id, () async {
      final page = await ref.read(apiProvider).feed(RepliesFeed(id), limit: repliesPerNode);
      return page.items;
    });
    cache.remember(id, replies, now);
    ref.read(postCacheProvider).remember(replies);
    // These carry current counts for the level below, which may invalidate what we
    // hold for their own replies.
    cache.noticeCounts(replies);
    return replies;
  }
}
