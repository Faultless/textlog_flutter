import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import 'cache.dart';
import 'feed.dart';
import 'providers.dart';

/// Writing happens in a browser tab, which gives no callback when it is finished.
/// Record what the write was aimed at, then refresh that — and only that — once the
/// app is back in the foreground.
sealed class PendingWrite {
  const PendingWrite();
}

final class PendingReply extends PendingWrite {
  const PendingReply(this.postId);
  final int postId;
}

final class PendingPost extends PendingWrite {
  const PendingPost();
}

final pendingWriteProvider = NotifierProvider<PendingWriteNotifier, PendingWrite?>(
  PendingWriteNotifier.new,
);

class PendingWriteNotifier extends Notifier<PendingWrite?> {
  @override
  PendingWrite? build() => null;

  void expect(PendingWrite write) => state = write;

  /// Called when the app returns to the foreground.
  void settle() {
    final pending = state;
    if (pending == null) return;
    state = null;

    switch (pending) {
      // Refresh the thread you replied to, not the feed you came from — invalidating
      // a feed resets it to the top and throws away the reader's place.
      case PendingReply(:final postId):
        // Evict first: postProvider serves the cache, so invalidating alone would
        // just hand back the same pre-reply copy.
        ref.read(postCacheProvider).forget(postId);
        ref.invalidate(postProvider(postId));
        ref.invalidate(feedProvider(RepliesFeed(postId)));
      case PendingPost():
        ref.invalidate(feedProvider(const LatestFeed()));
    }
  }
}
