import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feed_source.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/feed_view.dart';
import '../widgets/post_tile.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';
import 'web_action.dart';

const homeTabs = ['latest', 'hot', 'live'];
const homePaths = ['/', '/hot', '/live'];

/// All three tabs stay mounted: the live stream has to keep buffering while you
/// read elsewhere, and switching back should not refetch.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key, required this.tab});

  final int tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) => Scaffold(
    appBar: textlogAppBar(context, path: homePaths[tab]),
    floatingActionButton: FloatingActionButton.small(
      onPressed: () => openCompose(ref),
      backgroundColor: context.palette.accent,
      foregroundColor: context.palette.bg,
      elevation: 0,
      tooltip: 'write a post',
      child: const Icon(Icons.edit, size: 16),
    ),
    body: Column(
      children: [
        FeedTabs(
          tabs: homeTabs,
          active: tab,
          onSelect: (index) => context.go(homePaths[index]),
        ),
        Expanded(
          child: IndexedStack(
            index: tab,
            sizing: StackFit.expand,
            children: const [
              FeedView(LatestFeed()),
              FeedView(HotFeed()),
              LiveFeed(),
            ],
          ),
        ),
      ],
    ),
  );
}

class LiveFeed extends ConsumerWidget {
  const LiveFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posts = ref.watch(liveFeedProvider);
    final connection = ref.watch(firehoseProvider);

    if (posts.isEmpty) {
      return switch (connection) {
        AsyncError(:final error) => StatusMessage(
          messageFor(error),
          onRetry: () => ref.invalidate(firehoseProvider),
        ),
        _ => const _WaitingForPosts(),
      };
    }

    return ListView.builder(
      itemCount: posts.length,
      itemBuilder: (context, index) => PostTile(posts[index], showTopBorder: index > 0),
    );
  }
}

class _WaitingForPosts extends StatelessWidget {
  const _WaitingForPosts();

  @override
  Widget build(BuildContext context) => Column(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      const Spinner(),
      Padding(
        padding: EdgeInsets.symmetric(horizontal: gutterOf(context)),
        child: Text(
          'Waiting for new posts. They appear here as they are written.',
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(color: context.palette.muted),
        ),
      ),
    ],
  );
}
