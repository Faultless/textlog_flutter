import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../data/api.dart';
import '../data/firehose.dart';
import 'cache.dart';

/// Override this in tests to run the whole app against a fake server.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiProvider = Provider<TextlogApi>((ref) => TextlogApi(ref.watch(httpClientProvider)));

/// Served from [PostCache] when the post was already on screen, which is the usual
/// case — you tapped it, or it is the parent of a reply you are looking at.
final postProvider = FutureProvider.autoDispose.family<Post, int>((ref, id) async {
  cacheFor(ref, postCacheDuration);

  final cache = ref.watch(postCacheProvider);
  final known = cache[id];
  if (known != null) return known;

  final post = await ref.watch(apiProvider).post(id);
  cache.remember([post]);
  return post;
});

final profileProvider = FutureProvider.autoDispose.family<Profile, String>((ref, handle) {
  cacheFor(ref, postCacheDuration);
  return ref.watch(apiProvider).profile(handle);
});

final firehoseProvider = StreamProvider.autoDispose<Post>((ref) => firehose());

/// Newest-first buffer of posts seen on the live stream, bounded so a tab left
/// open overnight cannot grow without limit.
final liveFeedProvider = NotifierProvider.autoDispose<LiveFeedNotifier, List<Post>>(
  LiveFeedNotifier.new,
);

const _liveBufferLimit = 200;

class LiveFeedNotifier extends AutoDisposeNotifier<List<Post>> {
  @override
  List<Post> build() {
    ref.listen(firehoseProvider, (_, next) {
      final post = next.valueOrNull;
      if (post != null) {
        ref.read(postCacheProvider).remember([post]);
        state = [post, ...state.take(_liveBufferLimit - 1)];
      }
    });
    return const [];
  }
}
