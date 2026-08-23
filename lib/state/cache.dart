import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';

/// Keep an autoDispose provider alive for [duration] after its last listener goes,
/// instead of dropping it the instant you navigate away.
///
/// Without this, tapping into a thread and pressing back refetches the whole feed
/// and throws you to the top — the single thing that makes a Flutter app feel like
/// a website. With it, going back is instant and costs nothing.
void cacheFor(Ref<Object?> ref, Duration duration) {
  final link = ref.keepAlive();
  Timer? expiry;

  ref.onDispose(() => expiry?.cancel());
  ref.onCancel(() => expiry = Timer(duration, link.close));
  ref.onResume(() {
    expiry?.cancel();
    expiry = null;
  });
}

/// Clock seam, so tests can age the cache without waiting.
final nowProvider = Provider<DateTime Function()>((ref) => DateTime.now);

const feedCacheDuration = Duration(minutes: 5);
const postCacheDuration = Duration(minutes: 5);

/// Posts already seen in any feed this session.
///
/// A thread's root and a reply's quoted parent are nearly always posts that were
/// just on screen, so serving them from here turns the most common navigation in
/// the app — tapping a post — into zero requests.
final class PostCache {
  static const _limit = 500;

  final _posts = <int, Post>{};

  Post? operator [](int id) => _posts[id];

  void remember(Iterable<Post> posts) {
    for (final post in posts) {
      _write(post);
      // The server inlines the quoted parent on every post it returns. Keeping it
      // here is what makes tapping a quote free, and it gives the quote's own meta
      // line a chance to name who *it* was replying to.
      if (post.parent case final parent?) _write(parent);
    }
    // Dart maps keep insertion order, so the oldest entries are simply the first.
    if (_posts.length > _limit) {
      for (final id in _posts.keys.take(_posts.length - _limit).toList()) {
        _posts.remove(id);
      }
    }
  }

  /// Drop a post whose server state we know has changed, so the next read refetches.
  void forget(int id) => _posts.remove(id);

  /// Write a post we just changed straight into the cache, so the screen behind a
  /// sheet is already correct when it closes rather than flickering through a refetch.
  void replace(Post post) => _posts[post.id] = post;

  /// A quoted copy carries no parent of its own, so taking it wholesale over a full
  /// copy would lose a quote we already had. Take the fresher body and count, keep
  /// whichever parent is actually known.
  void _write(Post post) {
    final held = _posts[post.id];
    _posts[post.id] = post.parent == null && held?.parent != null
        ? post.copyWith(parent: held!.parent)
        : post;
  }
}

final postCacheProvider = Provider<PostCache>((ref) => PostCache());

/// How long a node's replies are trusted before a revalidation pass will refetch
/// them. textlog is a micro-blog: a thread that was quiet a few minutes ago is
/// almost certainly still quiet, and the server allows 120 requests a minute.
const repliesTtl = Duration(minutes: 5);

final class CachedReplies {
  const CachedReplies(this.posts, this.fetchedAt, {this.observedReplyCount});

  final List<Post> posts;
  final DateTime fetchedAt;

  /// The parent's own `reply_count` as it read when these replies were cached.
  ///
  /// Needed because `reply_count` is a post's *whole descendant* count, not the
  /// number of direct children — so it cannot be compared against `posts.length`.
  /// Doing that treated almost every node with a grandchild as out of date and threw
  /// its replies away on every feed fetch. Null when it was never observed, which
  /// means "no opinion" rather than "stale".
  final int? observedReplyCount;

  bool isStale(DateTime now) => now.difference(fetchedAt) > repliesTtl;
}

/// Replies fetched per request. The API allows 100, and a depth request pulls a
/// whole subtree, so ask for the lot.
const repliesPerNode = 100;

/// A subtree we fetched in one request, and how deep it went.
///
/// The per-parent lists below are what the tree is *assembled* from; this records
/// what a single request already covered, so reopening a thread does not pay for it
/// again — and so a deeper open than the cache holds still refetches.
final class CachedSubtree {
  const CachedSubtree(this.depth, this.fetchedAt);

  final int depth;
  final DateTime fetchedAt;

  bool isStale(DateTime now) => now.difference(fetchedAt) > repliesTtl;
}

/// Replies keyed by the post they belong to, kept for the whole session rather than
/// per screen.
///
/// This is what stops the app hammering `/posts/{id}/replies`. Assembling one thread
/// costs a request per branching node, so without it: reopening a thread pays again,
/// following a "+N more" link pays again for levels its parent already fetched, and
/// going back and forward a few times is enough to get rate limited.
final class RepliesCache {
  static const _limit = 200;

  final _byParent = <int, CachedReplies>{};
  final _subtrees = <int, CachedSubtree>{};
  final _inFlight = <int, Future<List<Post>>>{};

  /// Drop cached replies that the server has since contradicted.
  ///
  /// Every post carries its own `reply_count`, and feeds, the firehose and a single
  /// post fetch all return a current one. That makes it the cheapest change signal
  /// the API gives us: if a post now claims more replies than we hold for it, our
  /// copy is provably out of date and the next read should refetch — no polling, and
  /// no waiting for a TTL to lapse.
  ///
  /// A node holding a full page is skipped, because there the counts can legitimately
  /// disagree and we cannot tell staleness from truncation.
  void noticeCounts(Iterable<Post> posts) {
    for (final post in posts) {
      final cached = _byParent[post.id];
      if (cached == null || cached.posts.length >= repliesPerNode) continue;
      // Like against like: the count we saw when we cached, against the count now.
      final observed = cached.observedReplyCount;
      if (observed == null || post.replyCount == observed) continue;
      // forget, not a bare remove: the subtree mark rooted here claimed to cover
      // these replies, and it no longer does.
      forget(post.id);
    }
  }

  CachedReplies? operator [](int parentId) => _byParent[parentId];

  /// Collapse concurrent fetches of the same node into one request.
  ///
  /// A thread screen can be built more than once during a route transition, and two
  /// builds racing each other both miss the cache and both hit the network. Sharing
  /// the in-flight future makes the second one free.
  Future<List<Post>> fetchOnce(int parentId, Future<List<Post>> Function() fetch) {
    final existing = _inFlight[parentId];
    if (existing != null) return existing;

    final pending = fetch();
    _inFlight[parentId] = pending;
    return pending.whenComplete(() => _inFlight.remove(parentId));
  }

  void remember(int parentId, List<Post> posts, DateTime now, {int? replyCount}) {
    _byParent[parentId] = CachedReplies(posts, now, observedReplyCount: replyCount);
    if (_byParent.length > _limit) {
      for (final id in _byParent.keys.take(_byParent.length - _limit).toList()) {
        _byParent.remove(id);
      }
    }
  }

  void forget(int parentId) {
    _byParent.remove(parentId);
    // The subtree rooted here no longer covers what it claimed. Subtrees rooted
    // *above* this node keep their mark: assembling from them will find no entry
    // for this parent and advertise its replies as unloaded, which is the honest
    // answer and costs one tap rather than a refetch of the whole thread.
    _subtrees.remove(parentId);
  }

  /// How deep the subtree rooted at [rootId] was fetched, or null if never.
  CachedSubtree? subtree(int rootId) => _subtrees[rootId];

  /// Record a one-request subtree fetch, and what each node inside it covers.
  ///
  /// A node three levels down a five-level fetch has two levels below it, so it is
  /// marked as covered to depth two. That is what stops opening that node from
  /// showing a shallower tree than a fresh request would.
  /// [replyCounts] is each parent's own `reply_count` from the same response, so a
  /// later response can tell whether that subtree has changed.
  void rememberSubtree(
    int rootId,
    int depth,
    DateTime now,
    Map<int, List<Post>> loaded, {
    Map<int, int> replyCounts = const {},
  }) {
    _mark(rootId, depth, now);
    for (final entry in loaded.entries) {
      remember(entry.key, entry.value, now, replyCount: replyCounts[entry.key]);
    }
    // Walk down from the root, spending a level at each step.
    var frontier = [rootId];
    for (var remaining = depth - 1; remaining > 0 && frontier.isNotEmpty; remaining--) {
      final next = <int>[];
      for (final id in frontier) {
        for (final post in loaded[id] ?? const <Post>[]) {
          _mark(post.id, remaining, now);
          next.add(post.id);
        }
      }
      frontier = next;
    }
  }

  void _mark(int rootId, int depth, DateTime now) {
    final existing = _subtrees[rootId];
    // Never downgrade: a deeper fetch already covers a shallower one.
    if (existing != null && existing.depth >= depth && !existing.isStale(now)) return;
    _subtrees[rootId] = CachedSubtree(depth, now);
    if (_subtrees.length > _limit) {
      for (final id in _subtrees.keys.take(_subtrees.length - _limit).toList()) {
        _subtrees.remove(id);
      }
    }
  }

  /// Apply a local change to every cached reply list holding this post. Used after an
  /// edit or a delete so threads update without waiting on the network.
  void apply(int postId, Post? updated) {
    for (final entry in _byParent.entries.toList()) {
      final index = entry.value.posts.indexWhere((post) => post.id == postId);
      if (index < 0) continue;
      final posts = [...entry.value.posts];
      if (updated == null) {
        posts.removeAt(index);
      } else {
        posts[index] = updated;
      }
      _byParent[entry.key] = CachedReplies(
        posts,
        entry.value.fetchedAt,
        observedReplyCount: entry.value.observedReplyCount,
      );
    }
  }
}

final repliesCacheProvider = Provider<RepliesCache>((ref) => RepliesCache());
