import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../core/models.dart';
import '../data/api.dart';
import '../data/firehose.dart';

/// Override this in tests to run the whole app against a fake server.
final httpClientProvider = Provider<http.Client>((ref) {
  final client = http.Client();
  ref.onDispose(client.close);
  return client;
});

final apiProvider = Provider<TextlogApi>((ref) => TextlogApi(ref.watch(httpClientProvider)));

final postProvider = FutureProvider.autoDispose.family<Post, int>(
  (ref, id) => ref.watch(apiProvider).post(id),
);

final profileProvider = FutureProvider.autoDispose.family<Profile, String>(
  (ref, handle) => ref.watch(apiProvider).profile(handle),
);

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
        state = [post, ...state.take(_liveBufferLimit - 1)];
      }
    });
    return const [];
  }
}
