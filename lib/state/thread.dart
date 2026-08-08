import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import '../core/models.dart';
import '../core/reply_tree.dart';
import 'cache.dart';
import 'providers.dart';

/// How many levels to nest before a branch becomes a "N more replies" link.
const maxThreadDepth = 5;

/// Hard ceiling on requests for one thread. A wide thread would otherwise cost a
/// request per branching node, and the reader is waiting for all of them.
const maxThreadRequests = 24;

/// Replies per node. The API allows 100; a node with more than this reports the
/// remainder as unloaded rather than paginating inside the tree.
const repliesPerNode = 50;

final threadProvider = FutureProvider.autoDispose.family<List<ReplyNode>, int>((
  ref,
  rootId,
) async {
  cacheFor(ref, postCacheDuration);

  final api = ref.watch(apiProvider);
  final cache = ref.read(postCacheProvider);
  final loaded = <int, List<Post>>{};

  var frontier = [rootId];
  var budget = maxThreadRequests;

  // Breadth-first, one level at a time, fetching each level in parallel — a
  // sequential walk would make a five-deep thread feel like five round trips.
  for (var depth = 0; depth < maxThreadDepth && frontier.isNotEmpty && budget > 0; depth++) {
    final batch = frontier.take(budget).toList();
    budget -= batch.length;

    final pages = await Future.wait([
      for (final id in batch) api.feed(RepliesFeed(id), limit: repliesPerNode),
    ]);

    final next = <int>[];
    for (final (index, page) in pages.indexed) {
      loaded[batch[index]] = page.items;
      cache.remember(page.items);
      next.addAll(page.items.where((post) => post.replyCount > 0).map((post) => post.id));
    }
    frontier = next;
  }

  return assembleReplies(rootId, loaded, maxDepth: maxThreadDepth);
});
