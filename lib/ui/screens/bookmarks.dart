import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feed_source.dart';
import '../../state/bookmarks.dart';
import '../../state/feed.dart';
import '../widgets/feed_view.dart';
import '../widgets/shell.dart';

/// `/bookmarks` — the posts you kept, newest kept first.
///
/// Server side, like drafts: what you bookmark on the website is here, and what you
/// bookmark here is there. Nothing marks a post as kept in a feed — the API carries
/// no such field — so this screen is also where the app learns which posts it can
/// offer to un-keep. See [bookmarksProvider].
class BookmarksScreen extends ConsumerWidget {
  const BookmarksScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // What is on this page is, by definition, kept — so the menu on those posts can
    // offer to remove the bookmark rather than guessing. After the frame, because
    // this runs during a build and it writes to another provider; noticing what is
    // already known changes nothing, so it settles in one pass.
    final feed = ref.watch(feedProvider(const BookmarksFeed())).valueOrNull;
    if (feed != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        ref
            .read(bookmarksProvider.notifier)
            .notice([for (final post in feed.posts) post.id]);
      });
    }

    return Scaffold(
      appBar: textlogAppBar(context, path: '/bookmarks', showBack: true),
      body: const ReadingColumn(
        child: FeedView(
          BookmarksFeed(),
          emptyMessage: 'Nothing kept yet. Bookmark a post and it waits here.',
          // The server returns whole conversations here only by accident of what you
          // kept; nesting them would claim a thread you did not bookmark.
          group: false,
        ),
      ),
    );
  }
}
