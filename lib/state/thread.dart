import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import '../core/models.dart';
import '../core/reply_tree.dart';
import 'cache.dart';
import 'providers.dart';

/// How many levels to nest before a branch becomes a "N more replies" link.
const maxThreadDepth = 5;

/// Hard ceiling on *network* requests for one pass over a thread. The server allows
/// 120 JSON requests a minute, and a thread costs a request per branching node, so
/// without a ceiling a handful of wide threads would rate-limit the reader. Cached
/// nodes do not count against it.
const maxThreadRequests = 16;

/// Replies per node. The API allows 100; a node with more than this reports the
/// remainder as unloaded rather than paginating inside the tree.
const repliesPerNode = 50;

/// Clock seam, so tests can age the cache without waiting.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

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

    final tree = await _walk(revalidate: false);

    // Everything came from cache and some of it has aged out. Show it now — it is
    // almost certainly still correct — and quietly bring it up to date behind the
    // reader rather than making them wait on a spinner.
    if (_hasStaleEntries()) {
      Future<void>.microtask(() async {
        if (_disposed) return;
        final fresh = await _walk(revalidate: true);
        // The reader may have left while that was in flight.
        if (!_disposed) state = AsyncData(fresh);
      });
    }

    return tree;
  }

  /// Pull-to-refresh: refetch anything past its TTL, keep the rest.
  Future<void> refresh() async {
    final fresh = await _walk(revalidate: true);
    state = AsyncData(fresh);
  }

  bool _hasStaleEntries() {
    final cache = ref.read(repliesCacheProvider);
    final now = ref.read(nowProvider)();
    return _visited.any((id) => cache[id]?.isStale(now) ?? false);
  }

  /// Ids this notifier has walked, so revalidation knows the shape without refetching.
  final _visited = <int>{};

  Future<List<ReplyNode>> _walk({required bool revalidate}) async {
    final loaded = <int, List<Post>>{};
    _visited.clear();

    var frontier = [arg];
    var budget = maxThreadRequests;

    for (var depth = 0; depth < maxThreadDepth && frontier.isNotEmpty; depth++) {
      final results = await Future.wait([
        for (final id in frontier) _replies(id, revalidate: revalidate, budget: () => budget--),
      ]);

      final next = <int>[];
      for (final (index, replies) in results.indexed) {
        if (replies == null) continue; // budget ran out; the branch stays "N more"
        final id = frontier[index];
        loaded[id] = replies;
        _visited.add(id);
        next.addAll(replies.where((post) => post.replyCount > 0).map((post) => post.id));
      }
      frontier = next;
    }

    return assembleReplies(arg, loaded, maxDepth: maxThreadDepth);
  }

  /// Returns null when the request budget is spent, so the caller can leave that
  /// branch advertised-but-unloaded instead of dropping it.
  Future<List<Post>?> _replies(
    int id, {
    required bool revalidate,
    required int Function() budget,
  }) async {
    final cache = ref.read(repliesCacheProvider);
    final now = ref.read(nowProvider)();
    final hit = cache[id];

    // A cached node costs nothing and does not touch the budget. Only a revalidation
    // pass looks at how old it is.
    if (hit != null && !(revalidate && hit.isStale(now))) return hit.posts;

    if (budget() <= 0) return hit?.posts;

    final replies = await cache.fetchOnce(id, () async {
      final page = await ref.read(apiProvider).feed(RepliesFeed(id), limit: repliesPerNode);
      return page.items;
    });
    cache.remember(id, replies, now);
    ref.read(postCacheProvider).remember(replies);
    return replies;
  }
}
