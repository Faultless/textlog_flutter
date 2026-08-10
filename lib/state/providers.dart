import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/feed_source.dart';
import '../core/models.dart';
import '../data/api.dart';
import '../data/firehose.dart';
import 'cache.dart';
import 'rate_limit.dart';

/// Override this in tests to run the whole app against a fake server.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiProvider = Provider<TextlogApi>((ref) {
  final gate = ref.watch(rateLimitProvider);
  return TextlogApi(
    ref.watch(httpClientProvider),
    onResult: (failure) {
      final now = ref.read(nowProvider)();
      if (failure == null) {
        gate.clear();
      } else if (failure.isRateLimited) {
        gate.trip(now, failure.retryAfter);
      }
    },
  );
});

/// Served from [PostCache] when the post was already on screen, which is the usual
/// case — you tapped it, or it is the parent of a reply you are looking at.
final postProvider = FutureProvider.autoDispose.family<Post, int>((ref, id) async {
  cacheFor(ref, postCacheDuration);

  final cache = ref.watch(postCacheProvider);
  final known = cache[id];
  if (known != null) return known;

  final post = await ref.watch(apiProvider).post(id);
  cache.remember([post]);
  ref.read(repliesCacheProvider).noticeCounts([post]);
  return post;
});

final profileProvider = FutureProvider.autoDispose.family<Profile, String>((ref, handle) {
  cacheFor(ref, postCacheDuration);
  return ref.watch(apiProvider).profile(handle);
});

final firehoseProvider = StreamProvider.autoDispose<FirehoseEvent>((ref) => firehose());

/// Newest-first buffer of posts seen on the live stream, bounded so a tab left
/// open overnight cannot grow without limit.
final liveFeedProvider = NotifierProvider.autoDispose<LiveFeedNotifier, List<Post>>(
  LiveFeedNotifier.new,
);

const _liveBufferLimit = 200;
const _reconcileWindow = 30;

class LiveFeedNotifier extends AutoDisposeNotifier<List<Post>> {
  /// The newest post that existed when this tab was opened. Everything above it
  /// belongs in the live list.
  ///
  /// Deliberately fixed for the session rather than tracking the newest post seen.
  /// A moving mark loses posts: if the stream comes back and delivers a new post
  /// before reconciliation finishes, the mark jumps past the older posts still
  /// missing from the gap, and they never arrive.
  int? _since;
  var _primed = false;

  @override
  List<Post> build() {
    ref.listen(firehoseProvider, (_, next) {
      switch (next.valueOrNull) {
        case FirehoseConnected():
          _reconcile();
        case FirehosePost(:final post):
          ref.read(postCacheProvider).remember([post]);
          _noticeReply(post);
          _merge([post]);
        case null:
          break;
      }
    });
    return const [];
  }

  /// The server drops the stream every few seconds and does not honour
  /// `Last-Event-ID`, so posts published in the gap are simply gone from its point of
  /// view. `/feeds/latest` is the only way to find out what they were.
  Future<void>? _reconciling;

  /// Connection events can arrive in pairs — the transport's own `open` alongside a
  /// reconnect — and two overlapping reconciliations are two identical requests.
  Future<void> _reconcile() =>
      _reconciling ??= _fetchMissed().whenComplete(() => _reconciling = null);

  Future<void> _fetchMissed() async {
    try {
      final page = await ref
          .read(apiProvider)
          .feed(const LatestFeed(), limit: _reconcileWindow);

      if (!_primed) {
        // First connection. Note where "now" is, but do not tip the existing backlog
        // into a tab whose whole point is showing what arrives while you watch.
        _primed = true;
        _since = page.items.isEmpty ? null : page.items.first.id;
        return;
      }

      ref.read(repliesCacheProvider).noticeCounts(page.items);

      final since = _since;
      _merge(page.items.where((post) => since == null || post.id > since));
    } catch (_) {
      // A failed reconciliation just means the next reconnect tries again.
    }
  }

  /// A live post that is itself a reply tells us its parent's thread has changed,
  /// even though the parent's own reply_count is not in this payload. Dropping the
  /// parent's cached replies is what makes the new message appear when you open it.
  void _noticeReply(Post post) {
    if (post.parentId case final parentId?) {
      ref.read(repliesCacheProvider).forget(parentId);
      ref.read(postCacheProvider).forget(parentId);
    }
  }

  void _merge(Iterable<Post> posts) {
    final known = {for (final post in state) post.id};
    final fresh = posts.where((post) => !known.contains(post.id)).toList();
    if (fresh.isEmpty) return;

    final merged = [...fresh, ...state]..sort((a, b) => b.id.compareTo(a.id));
    state = merged.take(_liveBufferLimit).toList();
  }
}
