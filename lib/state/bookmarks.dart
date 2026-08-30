import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/feed_source.dart';
import 'feed.dart';
import 'providers.dart';
import 'session.dart';

/// What this session knows about which posts the reader has kept.
///
/// Not everything, and it cannot be: a post in a feed does not say whether it is
/// bookmarked — the API carries no such field — so the only posts whose state is
/// known are the ones in `/bookmarks` and the ones bookmarked here since launch.
/// Absent means *unknown*, not "no", which is why this is a map rather than a set:
/// the menu offers `bookmark` when it does not know, and that request is safe to
/// repeat.
final bookmarksProvider =
    NotifierProvider<BookmarksNotifier, Map<int, bool>>(BookmarksNotifier.new);

class BookmarksNotifier extends Notifier<Map<int, bool>> {
  @override
  Map<int, bool> build() => const {};

  /// The bookmarks screen, saying what it just loaded.
  void notice(Iterable<int> postIds) {
    final known = {...state, for (final id in postIds) id: true};
    if (known.length != state.length) state = known;
  }

  /// Keep [postId], or stop keeping it.
  ///
  /// Optimistic, like every other write in the app: the label changes on the tap,
  /// and a failure puts it back — this one *is* worth putting back, because unlike
  /// an unread mark the reader is asking for something and deserves to know it did
  /// not happen.
  Future<void> toggle(int postId, {required bool bookmarked}) async {
    final token = ref.read(viewerProvider)?.token;
    if (token == null) return;

    final before = state;
    state = {...state, postId: bookmarked};
    try {
      await ref.read(apiProvider).bookmark(token, postId, bookmarked: bookmarked);
      // The collection changed, and it is a server-ordered list the app cannot
      // reorder for itself.
      ref.invalidate(feedProvider(const BookmarksFeed()));
    } catch (_) {
      state = before;
      rethrow;
    }
  }
}
