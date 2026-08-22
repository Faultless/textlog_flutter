import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feed_source.dart';
import '../../data/api.dart';
import '../../state/activity.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../theme.dart';
import '../widgets/activity_view.dart';
import '../widgets/compose_sheet.dart';
import '../widgets/feed_view.dart';
import '../widgets/post_tile.dart';
import '../widgets/pressable.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';
import 'web_action.dart';

/// The tabs the site offers, in its order, plus `live` — which the site cannot have
/// and a phone is the right place for.
///
/// `for you` and `to me` need a token, so they are only mounted when there is one.
/// That is also why the tab list is computed rather than constant: the set changes
/// when you sign in.
enum HomeTab {
  forYou('for you', '/for-you', authenticated: true),
  toMe('to me', '/to-me', authenticated: true),
  hot('hot', '/hot'),
  latest('latest', '/latest'),
  live('live', '/live');

  const HomeTab(this.label, this.path, {this.authenticated = false});

  final String label;
  final String path;

  /// Offered only to a signed-in reader.
  final bool authenticated;

  static List<HomeTab> visible({required bool signedIn}) =>
      values.where((tab) => signedIn || !tab.authenticated).toList();

  static HomeTab? ofPath(String path) =>
      values.where((tab) => tab.path == path).firstOrNull;
}

/// Where `/` lands. The site sends an anonymous reader to `hot` and a signed-in one
/// to their own feed, and so does this.
String homeRedirect({required bool signedIn}) =>
    signedIn ? HomeTab.forYou.path : HomeTab.hot.path;

/// Tabs mount on first visit and stay: the live stream keeps buffering while you
/// read elsewhere, and switching back should not refetch. Building all of them up
/// front would fetch four feeds and open the firehose to show one.
class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key, required this.tab});

  final HomeTab tab;

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  final _visited = <HomeTab>{};

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).valueOrNull;
    final signedIn = session != null;
    final tabs = HomeTab.visible(signedIn: signedIn);

    // Signing out with `to me` open leaves you on a tab that no longer exists.
    final tab = tabs.contains(widget.tab) ? widget.tab : HomeTab.hot;
    _visited.add(tab);

    Future<void> write() async {
      if (session == null) {
        await openCompose(ref);
        return;
      }
      await showCompose(context);
    }

    final plain = context.chrome.plain;

    return Scaffold(
      appBar: textlogAppBar(context, path: tab.path),
      // A floating circle is the single most Material thing in the app, so barebones
      // trades it for a `+ write` link in the tab row.
      floatingActionButton: plain
          ? null
          : FloatingActionButton.small(
              onPressed: write,
              backgroundColor: context.palette.accent,
              foregroundColor: context.palette.bg,
              elevation: 0,
              tooltip: 'write a post',
              child: const Icon(Icons.edit, size: 16),
            ),
      body: Column(
        children: [
          FeedTabs(
            tabs: [
              for (final entry in tabs)
                TabSpec(
                  entry.label,
                  entry.path,
                  marked: switch (entry) {
                    HomeTab.forYou => ref.watch(activityUnreadProvider(ActivityScope.forYou)),
                    HomeTab.toMe => ref.watch(activityUnreadProvider(ActivityScope.toMe)),
                    _ => false,
                  },
                ),
            ],
            active: tabs.indexOf(tab),
            onSelect: (index) => context.go(tabs[index].path),
            trailing: switch (tab) {
              HomeTab.forYou => const _MarkAllRead(ActivityScope.forYou),
              HomeTab.toMe => const _MarkAllRead(ActivityScope.toMe),
              _ => null,
            },
          ),
          Expanded(
            child: IndexedStack(
              index: tabs.indexOf(tab),
              sizing: StackFit.expand,
              children: [
                for (final entry in tabs)
                  if (_visited.contains(entry)) _pane(entry) else const SizedBox.shrink(),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _pane(HomeTab tab) => switch (tab) {
    HomeTab.forYou => const ActivityView(ActivityScope.forYou),
    HomeTab.toMe => const ActivityView(ActivityScope.toMe),
    HomeTab.hot => const FeedView(HotFeed()),
    HomeTab.latest => const FeedView(LatestFeed()),
    HomeTab.live => const LiveFeed(),
  };
}

/// `mark all as read`, which the site puts in the same corner.
class _MarkAllRead extends ConsumerWidget {
  const _MarkAllRead(this.scope);

  final ActivityScope scope;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme.labelSmall!;
    final unread = ref.watch(activityUnreadProvider(scope));

    if (!unread) {
      return Text("you've seen it all", style: theme.copyWith(color: palette.muted));
    }
    return Pressable(
      onTap: () => ref.read(activityProvider(scope).notifier).markAllRead(),
      builder: (context, pressed) => Text(
        'mark all as read',
        style: theme.asLink(palette).copyWith(color: pressed ? palette.accent : null),
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
