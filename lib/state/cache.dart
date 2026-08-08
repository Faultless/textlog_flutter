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
}

final postCacheProvider = Provider<PostCache>((ref) => PostCache());
