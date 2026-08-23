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

/// Ceiling on network requests for one pass. Cached subtrees are free.
///
/// It used to take one request per branching node, so this was eight. The server
/// now walks the tree for us — `?depth=` returns a whole subtree flat — so opening a
/// thread is *one* request and the rest of the allowance only ever goes on branches
/// the reader explicitly asked to expand.
const maxThreadRequests = 4;

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
    return _roots.any((id) => cache.subtree(id)?.isStale(now) ?? false);
  }

  /// Subtree roots this notifier has walked, so revalidation knows what to check.
  final _roots = <int>{};

  /// Branches we have asked the server to walk: the thread itself, plus whatever the
  /// reader expanded because the first request could not reach it.
  late final _expanded = <int>{arg};

  bool isExpanded(int id) => _expanded.contains(id);

  /// One request. Everything already loaded is reused.
  Future<void> expand(int id) async {
    if (!_expanded.add(id)) return;
    state = AsyncData(await _walk(ThreadFetch.cached));
  }

  Future<List<ReplyNode>> _walk(ThreadFetch mode) async {
    final loaded = <int, List<Post>>{};
    _roots.clear();
    var budget = maxThreadRequests;

    // The thread's own root first, then anything the reader opened. Each is one
    // request that comes back with every level below it.
    for (final root in [arg, ..._expanded.where((id) => id != arg)]) {
      final subtree = await _subtree(root, mode: mode, budget: () => budget--);
      if (subtree == null) continue;
      _roots.add(root);
      // A deeper fetch of the same parent wins; both are current, and the later one
      // was asked for on purpose.
      loaded.addAll(subtree);
    }

    return assembleReplies(arg, loaded, maxDepth: maxThreadDepth);
  }

  /// The subtree below [rootId], grouped by parent, or null when there was nothing
  /// cached and no budget left to fetch it.
  Future<Map<int, List<Post>>?> _subtree(
    int rootId, {
    required ThreadFetch mode,
    required int Function() budget,
  }) async {
    final cache = ref.read(repliesCacheProvider);
    final now = ref.read(nowProvider)();
    final held = cache.subtree(rootId);

    // A subtree mark without the root's own entry means something invalidated it
    // since — a live reply, or a count that disagreed. Refetch rather than assemble
    // an empty tree out of it.
    final covered = held != null && held.depth >= maxThreadDepth && cache[rootId] != null;

    // A reused subtree costs nothing and does not touch the budget.
    final reuse = switch (mode) {
      ThreadFetch.cached => covered,
      ThreadFetch.revalidate => covered && !held.isStale(now),
      ThreadFetch.force => false,
    };
    if (reuse) return _fromCache(rootId, cache);

    if (budget() <= 0) return held == null ? null : _fromCache(rootId, cache);

    final posts = await cache.fetchOnce(rootId, () async {
      final page = await ref.read(apiProvider).feed(
        RepliesFeed(rootId, depth: maxThreadDepth),
        limit: repliesPerNode,
      );
      return page.items;
    });

    var grouped = _groupByParent(rootId, posts);
    var depth = maxThreadDepth;

    // More than one level of ancestors missing, which the inlined parents cannot
    // bridge. Rather than show an empty thread, spend one request on the level that
    // is always placeable. Rare, and bounded by the same budget as everything else.
    if (grouped[rootId]!.isEmpty && posts.isNotEmpty && budget() > 0) {
      final direct = await ref.read(apiProvider).feed(
        RepliesFeed(rootId),
        limit: repliesPerNode,
      );
      if (direct.items.isNotEmpty) {
        grouped = _groupByParent(rootId, direct.items);
        // Only the one level was fetched, so nothing below it is covered.
        depth = 1;
        ref.read(postCacheProvider).remember(direct.items);
      }
    }

    cache.rememberSubtree(
      rootId,
      depth,
      now,
      grouped,
      // Every parent in the response carries its own count. The thread's own root
      // does not appear in its own replies, so its count comes from the post cache
      // when that has seen it — without which a new reply to the root would not be
      // noticed until the entry aged out.
      replyCounts: {
        for (final post in posts) post.id: post.replyCount,
        if (ref.read(postCacheProvider)[rootId] case final root?)
          rootId: root.replyCount,
      },
    );
    ref.read(postCacheProvider).remember(posts);
    // Every post carries a current count for the level below it, which may
    // contradict replies we hold for nodes this request did not reach.
    cache.noticeCounts(posts);
    return grouped;
  }

  /// Read a subtree back out of the per-parent cache, walking down from the root so
  /// only entries that actually belong to this thread are picked up.
  Map<int, List<Post>> _fromCache(int rootId, RepliesCache cache) {
    final loaded = <int, List<Post>>{};
    var frontier = [rootId];
    for (var depth = 0; depth < maxThreadDepth && frontier.isNotEmpty; depth++) {
      final next = <int>[];
      for (final id in frontier) {
        final held = cache[id];
        if (held == null) continue;
        loaded[id] = held.posts;
        next.addAll(held.posts.where((post) => post.replyCount > 0).map((post) => post.id));
      }
      frontier = next;
    }
    return loaded;
  }

  /// A depth request answers with the subtree flat, each post carrying its
  /// `parent_id`. Grouping it is what turns one response into the tree.
  ///
  /// The page holds the **newest** hundred of the subtree, which is not the same as
  /// the top hundred: a busy branch deep in a thread can fill the whole page and
  /// leave its own ancestors off it. Those posts cannot be placed by `parent_id`
  /// alone, and dropping them meant a thread with a hundred and twenty replies
  /// rendered none at all.
  ///
  /// So a second pass rebuilds one missing level from the `parent` the server inlines
  /// on every post. That costs no request, which is the whole reason to do it that way.
  Map<int, List<Post>> _groupByParent(int rootId, List<Post> posts) {
    final grouped = <int, List<Post>>{rootId: []};
    final reachable = {rootId};
    final placed = <int>{};

    void place(Post post, int parentId) {
      (grouped[parentId] ??= []).add(post);
      reachable.add(post.id);
      placed.add(post.id);
    }

    // Ascending id order, so a parent is always seen before its children.
    final ordered = [...posts]..sort((a, b) => a.id.compareTo(b.id));

    for (final post in ordered) {
      final parentId = post.parentId;
      if (parentId != null && reachable.contains(parentId)) place(post, parentId);
    }

    for (final post in ordered) {
      if (placed.contains(post.id)) continue;
      final parent = post.parent;
      final grandparentId = parent?.parentId;
      // Only one level can be bridged this way: a quote carries no parent of its own.
      if (parent == null || grandparentId == null) continue;
      if (!reachable.contains(grandparentId)) continue;
      if (!placed.contains(parent.id)) place(parent, grandparentId);
      place(post, parent.id);
    }

    // A conversation reads oldest first, and the second pass appends out of order.
    for (final branch in grouped.values) {
      branch.sort((a, b) => a.id.compareTo(b.id));
    }
    return grouped;
  }
}
