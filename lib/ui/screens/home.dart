import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feed_source.dart';
import '../../core/tab_prefs.dart';
import '../../data/api.dart';
import '../../state/activity.dart';
import '../../state/settings.dart';
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

  /// Stable id for the preferences store — the enum name, not the label, so
  /// rewording a tab does not silently reset anyone's arrangement.
  String get id => name;

  static List<HomeTab> visible({required bool signedIn}) =>
      values.where((tab) => signedIn || !tab.authenticated).toList();

  /// What this reader sees: the tabs their sign-in state allows, in the order they
  /// chose, minus the ones they turned off.
  static List<HomeTab> forReader({
    required bool signedIn,
    required List<String> order,
    required Set<String> hidden,
  }) => arrangeTabs(
    visible(signedIn: signedIn),
    order: order,
    hidden: hidden,
    id: (tab) => tab.id,
  );

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
    final session = ref.watch(viewerProvider);
    final signedIn = session != null;
    final settings = ref.watch(settingsProvider).valueOrNull ?? const Settings();
    final tabs = HomeTab.forReader(
      signedIn: signedIn,
      order: settings.tabOrder,
      hidden: settings.hiddenTabs,
    );

    // Signing out with `to me` open leaves you on a tab that no longer exists.
    // A hidden tab reached by its own URL still renders: hiding is about the row,
    // not about walling off a link someone sent you.
    final tab = tabs.contains(widget.tab) ? widget.tab : tabs.first;
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
      body: ReadingColumn(
        child: Column(
          children: [
            FeedTabs(
              tabs: [
                for (final entry in tabs)
                  TabSpec(
                    entry.label,
                    entry.path,
                    marked: switch (entry) {
                      HomeTab.forYou =>
                        ref.watch(activityUnreadProvider(ActivityScope.forYou)),
                      HomeTab.toMe => ref.watch(activityUnreadProvider(ActivityScope.toMe)),
                      _ => false,
                    },
                  ),
              ],
              active: tabs.indexOf(tab),
              onSelect: (index) => context.go(tabs[index].path),
              trailing: switch (tab) {
                HomeTab.forYou => (compact) =>
                  _MarkAllRead(ActivityScope.forYou, compact: compact),
                HomeTab.toMe => (compact) =>
                  _MarkAllRead(ActivityScope.toMe, compact: compact),
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
///
/// On a narrow row it shortens, and the "nothing left to read" status disappears
/// entirely — it is information, not an action, and it was costing more than half
/// the tab row to say something the absent unread dots already say.
class _MarkAllRead extends ConsumerWidget {
  const _MarkAllRead(this.scope, {required this.compact});

  final ActivityScope scope;
  final bool compact;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme.labelSmall!;
    final unread = ref.watch(activityUnreadProvider(scope));

    if (!unread) {
      if (compact) return const SizedBox.shrink();
      return Text(
        "you've seen it all",
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: theme.copyWith(color: palette.muted),
      );
    }
    return Pressable(
      onTap: () => ref.read(activityProvider(scope).notifier).markAllRead(),
      semanticLabel: 'mark all as read',
      builder: (context, pressed) => Text(
        compact ? 'mark read' : 'mark all as read',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
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
          onRetry: () => ref.refresh(firehoseProvider.future),
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
