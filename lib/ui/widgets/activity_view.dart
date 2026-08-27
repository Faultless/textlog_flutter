import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../core/seen.dart';
import '../../data/api.dart';
import '../../state/activity.dart';
import '../../state/settings.dart';
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
///
/// Reading one also marks it: a row that has been fully on screen has been read, and
/// scrolling past everything used to leave every dot in place until you pressed
/// "mark all as read" — a chore you had already done by reading. See [seenRows] for
/// where the line is drawn.
class ActivityView extends ConsumerStatefulWidget {
  const ActivityView(this.scope, {super.key});

  final ActivityScope scope;

  @override
  ConsumerState<ActivityView> createState() => _ActivityViewState();
}

const _loadMoreThreshold = 600.0;

class _ActivityViewState extends ConsumerState<ActivityView> {
  final _controller = ScrollController();

  /// Keys for the unread rows currently built, so they can be measured. Only unread
  /// ones: there is nothing to learn about a row that is already read.
  final _unread = <String, GlobalKey>{};

  /// Already sent to the server. The notifier is optimistic, so a row stops being
  /// unread before the request lands and would otherwise be re-sent on every scroll.
  final _sent = <String>{};

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

  /// The rows this reader wants to see.
  ///
  /// Follows and tag-follows are activity but they are not *reading*: some readers
  /// want the posts and none of the who-followed-whom. Filtered in the app rather
  /// than asked of the server, which offers no such parameter — so the count the
  /// server reports as unread can exceed what is on screen, and a hidden row is
  /// never marked read on the reader's behalf.
  List<Activity> visible(List<Activity> items) {
    final wanted =
        ref.watch(settingsProvider).valueOrNull?.followNotices ?? true;
    if (wanted) return items;
    return [
      for (final item in items)
        if (item.kind != ActivityKind.userFollow &&
            item.kind != ActivityKind.tagFollow)
          item,
    ];
  }

  /// Measure the unread rows and mark the ones fully on screen.
  ///
  /// On scroll *end* rather than on every frame: flinging through a feed is not
  /// reading it, and a request per frame would be absurd besides.
  void _sweep() {
    if (!mounted) return;
    final viewport = _controller.hasClients ? context.findRenderObject() : null;
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final origin = viewport.localToGlobal(Offset.zero);
    final bounds = origin & viewport.size;

    final boxes = <String, Rect>{};
    for (final MapEntry(key: id, value: key) in _unread.entries) {
      if (_sent.contains(id)) continue;
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      boxes[id] = box.localToGlobal(Offset.zero) & box.size;
    }

    final seen = seenRows(boxes, bounds).toList();
    if (seen.isEmpty) return;
    _sent.addAll(seen);
    ref.read(activityProvider(widget.scope).notifier).markRead(seen);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(activityProvider(widget.scope));
    final notifier = ref.read(activityProvider(widget.scope).notifier);

    // After the frame this build produces, not just after a scroll: the rows already
    // on screen when the feed arrives count too, and at open there has been no
    // scroll to notice. Safe to schedule on every build — a sweep that marks nothing
    // new changes no state, so this settles after one pass rather than looping.
    if (feed.hasValue) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _sweep());
    }

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      color: context.palette.accent,
      backgroundColor: context.palette.panel,
      child: NotificationListener<ScrollEndNotification>(
        onNotification: (_) {
          _sweep();
          return false;
        },
        child: CustomScrollView(
          controller: _controller,
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: switch (feed) {
            AsyncData(:final value) when visible(value.items).isEmpty => [
              SliverToBoxAdapter(
                child: StatusMessage(
                  widget.scope == ActivityScope.toMe
                      ? 'Nothing addressed to you yet. Replies and mentions land here.'
                      : 'Nothing yet. Follow some accounts and hashtags and this fills up.',
                ),
              ),
            ],
            AsyncData(:final value) => [
              () {
                final items = visible(value.items);
                return SliverList.builder(
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final activity = items[index];
                    return _Row(
                      activity,
                      scope: widget.scope,
                      showTopBorder: index > 0,
                      // Keyed only while unread, and by id so a row keeps its key
                      // across the rebuild that inserts new activity above it.
                      measureKey:
                          activity.unread && !_sent.contains(activity.id)
                          ? _unread.putIfAbsent(activity.id, GlobalKey.new)
                          : null,
                    );
                  },
                );
              }(),
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
                child: StatusMessage(
                  messageFor(error),
                  onRetry: notifier.refresh,
                ),
              ),
            ],
            _ => const [SliverToBoxAdapter(child: Spinner())],
          },
        ),
      ),
    );
  }
}

class _Row extends ConsumerWidget {
  const _Row(
    this.activity, {
    required this.scope,
    required this.showTopBorder,
    this.measureKey,
  });

  final Activity activity;
  final ActivityScope scope;
  final bool showTopBorder;

  /// Set while this row is unread, so the list can measure where it is.
  final GlobalKey? measureKey;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;

    void read() =>
        ref.read(activityProvider(scope).notifier).markRead([activity.id]);

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
      key: measureKey,
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: palette.accent, width: 2)),
      ),
      child: body,
    );
  }
}

/// A follow, a tag follow or a signup — no post attached, so a single line.
class _Event extends ConsumerWidget {
  const _Event(
    this.activity, {
    required this.showTopBorder,
    required this.onOpen,
  });

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
      padding: EdgeInsets.symmetric(
        horizontal: gutterOf(context),
        vertical: space4,
      ),
      decoration: BoxDecoration(
        border: Border(
          top: showTopBorder
              ? BorderSide(color: palette.soft)
              : BorderSide.none,
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
                style: meta
                    .asLink(palette)
                    .copyWith(color: pressed ? palette.accent : null),
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
