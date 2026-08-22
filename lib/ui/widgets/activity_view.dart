import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../data/api.dart';
import '../../state/activity.dart';
import '../theme.dart';
import 'post_meta.dart';
import 'post_tile.dart';
import 'pressable.dart';
import 'status.dart';

/// `/for-you` and `/to-me` — the two feeds the ROADMAP listed as needing the server
/// first. They exist now, so they are here.
///
/// A row is either a post (someone you follow wrote, replied to you, mentioned you)
/// or a relationship event (someone followed someone, or a tag). Unread rows carry a
/// dot, and opening one marks it read on the spot rather than waiting on the server.
class ActivityView extends ConsumerStatefulWidget {
  const ActivityView(this.scope, {super.key});

  final ActivityScope scope;

  @override
  ConsumerState<ActivityView> createState() => _ActivityViewState();
}

const _loadMoreThreshold = 600.0;

class _ActivityViewState extends ConsumerState<ActivityView> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _maybeLoadMore() {
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      ref.read(activityProvider(widget.scope).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(activityProvider(widget.scope));
    final notifier = ref.read(activityProvider(widget.scope).notifier);

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      color: context.palette.accent,
      backgroundColor: context.palette.panel,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: switch (feed) {
          AsyncData(:final value) when value.items.isEmpty => [
            SliverToBoxAdapter(
              child: StatusMessage(
                widget.scope == ActivityScope.toMe
                    ? 'Nothing addressed to you yet. Replies and mentions land here.'
                    : 'Nothing yet. Follow some accounts and hashtags and this fills up.',
              ),
            ),
          ],
          AsyncData(:final value) => [
            SliverList.builder(
              itemCount: value.items.length,
              itemBuilder: (context, index) => _Row(
                value.items[index],
                scope: widget.scope,
                showTopBorder: index > 0,
              ),
            ),
            SliverToBoxAdapter(
              child: switch (value) {
                ActivityState(:final loadMoreError?) => StatusMessage(
                  messageFor(loadMoreError),
                  onRetry: () => notifier.loadMore(asked: true),
                ),
                ActivityState(hasMore: true) => const Spinner(),
                _ => const SizedBox(height: space6),
              },
            ),
          ],
          AsyncError(:final error) => [
            SliverToBoxAdapter(
              child: StatusMessage(messageFor(error), onRetry: notifier.refresh),
            ),
          ],
          _ => const [SliverToBoxAdapter(child: Spinner())],
        },
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row(this.activity, {required this.scope, required this.showTopBorder});

  final Activity activity;
  final ActivityScope scope;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    void read() => ref.read(activityProvider(scope).notifier).markRead([activity.id]);

    final body = switch (activity.post) {
      final post? => GestureDetector(
        // The tile handles its own navigation; this only records that you saw it.
        onTapDown: (_) => read(),
        child: PostTile(post, showTopBorder: showTopBorder),
      ),
      _ => _Event(activity, showTopBorder: showTopBorder, onOpen: read),
    };

    if (!activity.unread) return body;

    // `.unread-dot` — a hairline accent rail rather than a coloured background, which
    // on a dense monospace feed would read as selection.
    return Container(
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: palette.accent, width: 2)),
      ),
      child: body,
    );
  }
}

/// A follow, a tag follow or a signup — no post attached, so a single line.
class _Event extends ConsumerWidget {
  const _Event(this.activity, {required this.showTopBorder, required this.onOpen});

  final Activity activity;
  final bool showTopBorder;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final meta = theme.bodySmall!;
    final actor = activity.actor;
    if (actor == null) return const SizedBox.shrink();

    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space4),
      decoration: BoxDecoration(
        border: Border(
          top: showTopBorder ? BorderSide(color: palette.soft) : BorderSide.none,
        ),
      ),
      child: Wrap(
        spacing: space2,
        runSpacing: space1,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          HandleLink(actor.handle, style: meta, asYou: true),
          Text(_verb(activity), style: meta.copyWith(color: palette.muted)),
          if (activity.targetUser case final target?)
            HandleLink(target.handle, style: meta, asYou: true)
          else if (activity.targetTag case final tag?)
            Pressable(
              onTap: () {
                onOpen();
                context.push('/tag/$tag');
              },
              builder: (context, pressed) => Text(
                '#$tag',
                style: meta.asLink(palette).copyWith(
                  color: pressed ? palette.accent : null,
                ),
              ),
            ),
          PostMeta(createdAt: activity.createdAt, replyCount: 0, style: meta),
        ],
      ),
    );
  }

  String _verb(Activity activity) => switch (activity.kind) {
    ActivityKind.userFollow => 'followed',
    ActivityKind.tagFollow => 'followed',
    ActivityKind.signup => 'joined',
    _ => '',
  };
}
