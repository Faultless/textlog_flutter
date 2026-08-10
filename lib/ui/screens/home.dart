import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feed_source.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/feed_view.dart';
import '../widgets/post_tile.dart';
import '../widgets/shell.dart';
import '../../state/session.dart';
import '../widgets/compose_sheet.dart';
import '../widgets/status.dart';
import 'web_action.dart';

const homeTabs = ['latest', 'hot', 'live'];
const homePaths = ['/', '/hot', '/live'];

/// Tabs mount on first visit and stay: the live stream keeps buffering while you
/// read elsewhere, and switching back should not refetch. Building all three up
/// front fetched two feeds and opened the firehose to show one.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.tab});

  final int tab;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _visited = <int>{};

  @override
  Widget build(BuildContext context) {
    final tab = widget.tab;
    _visited.add(tab);

    const panes = [FeedView(LatestFeed()), FeedView(HotFeed()), LiveFeed()];

    return Scaffold(
      appBar: textlogAppBar(context, path: homePaths[tab]),
      floatingActionButton: FloatingActionButton.small(
        onPressed: () async {
          if (ref.read(sessionProvider).valueOrNull == null) {
            await openCompose(ref);
            return;
          }
          await showCompose(context);
        },
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
              children: [
                for (final (index, pane) in panes.indexed)
                  if (_visited.contains(index)) pane else const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }
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
