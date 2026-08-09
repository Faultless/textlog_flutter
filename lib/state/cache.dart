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
      _posts[post.id] = post;
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
}

final postCacheProvider = Provider<PostCache>((ref) => PostCache());

/// How long a node's replies are trusted before a revalidation pass will refetch
/// them. textlog is a micro-blog: a thread that was quiet a few minutes ago is
/// almost certainly still quiet, and the server allows 120 requests a minute.
const repliesTtl = Duration(minutes: 5);

final class CachedReplies {
  const CachedReplies(this.posts, this.fetchedAt);

  final List<Post> posts;
  final DateTime fetchedAt;

  bool isStale(DateTime now) => now.difference(fetchedAt) > repliesTtl;
}

/// Replies fetched per node. The API allows 100.
const repliesPerNode = 50;

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
      if (post.replyCount != cached.posts.length) _byParent.remove(post.id);
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

  void remember(int parentId, List<Post> posts, DateTime now) {
    _byParent[parentId] = CachedReplies(posts, now);
    if (_byParent.length > _limit) {
      for (final id in _byParent.keys.take(_byParent.length - _limit).toList()) {
        _byParent.remove(id);
      }
    }
  }

  void forget(int parentId) => _byParent.remove(parentId);

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
      _byParent[entry.key] = CachedReplies(posts, entry.value.fetchedAt);
    }
  }
}

final repliesCacheProvider = Provider<RepliesCache>((ref) => RepliesCache());
