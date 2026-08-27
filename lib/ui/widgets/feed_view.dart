import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feed_source.dart';
import '../../core/feed_tree.dart';
import '../../core/seen.dart';
import '../../state/feed.dart';
import '../../core/search.dart';
import '../theme.dart';
import 'post_tile.dart';
import 'reply_tree.dart';
import 'status.dart';

/// The whole reading experience: give it a [FeedSource] and it paginates, refreshes
/// and recovers on its own. [header] is an optional sliver pinned above the posts.
class FeedView extends ConsumerStatefulWidget {
  const FeedView(
    this.source, {
    super.key,
    this.header,
    this.emptyMessage = 'Nothing here yet.',
    this.allowFilter = true,
    this.group = true,
  });

  final FeedSource source;
  final Widget? header;
  final String emptyMessage;

  /// Off where a server-side query already narrowed the list; filtering the results
  /// of a search reads as the search having broken.
  final bool allowFilter;

  /// Join replies to parents on the same page into a thread. Off where the feed is
  /// a list of one author's replies and nesting them under each other would misread
  /// the page as a conversation.
  final bool group;

  @override
  ConsumerState<FeedView> createState() => _FeedViewState();
}

const _loadMoreThreshold = 600.0;

class _FeedViewState extends ConsumerState<FeedView> {
  final _controller = ScrollController();
  final _search = TextEditingController();

  /// Keys for the unread posts on screen, and the ids already sent. Same machinery
  /// as the activity feeds, for the same reason: scrolling past something is reading
  /// it, and the reader should not have to say so afterwards.
  final _unread = <int, GlobalKey>{};
  final _sent = <int>{};

  @override
  void initState() {
    super.initState();
    _controller.addListener(_maybeLoadMore);
  }

  @override
  void dispose() {
    _controller.dispose();
    _search.dispose();
    super.dispose();
  }

  /// Shown once a timeline is long enough that scrolling for something is a chore.
  static const _searchAfter = 15;

  void _maybeLoadMore() {
    final position = _controller.position;
    if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
      ref.read(feedProvider(widget.source).notifier).loadMore();
    }
  }

  /// Mark the unread posts that have been fully on screen. See `core/seen.dart` for
  /// where the line is drawn and why `fully` is the whole point.
  void _sweep() {
    if (!mounted || _unread.isEmpty) return;
    final viewport = context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return;
    final bounds = viewport.localToGlobal(Offset.zero) & viewport.size;

    final boxes = <String, Rect>{};
    for (final MapEntry(key: id, value: key) in _unread.entries) {
      if (_sent.contains(id)) continue;
      final box = key.currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      boxes['$id'] = box.localToGlobal(Offset.zero) & box.size;
    }

    final seen = [for (final id in seenRows(boxes, bounds)) int.parse(id)];
    if (seen.isEmpty) return;
    _sent.addAll(seen);
    ref.read(feedProvider(widget.source).notifier).markRead(seen);
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider(widget.source));
    final notifier = ref.read(feedProvider(widget.source).notifier);

    // Only the latest feed reports unread, and only signed in.
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
          slivers: [
            if (widget.header != null) widget.header!,
            ...switch (feed) {
              AsyncData(:final value) when value.posts.isEmpty => [
                SliverToBoxAdapter(child: StatusMessage(widget.emptyMessage)),
              ],
              AsyncData(:final value) => () {
                final query = widget.allowFilter ? _search.text : '';
                final posts = searchPosts(value.posts, query);
                final filtering = query.trim().isNotEmpty;
                final filter = SliverToBoxAdapter(
                  child: _Filter(_search, () => setState(() {})),
                );

                if (posts.isEmpty) {
                  return [
                    filter,
                    SliverToBoxAdapter(
                      child: StatusMessage('Nothing loaded matches that.'),
                    ),
                  ];
                }
                // Join replies to parents that are on the same page, so a busy
                // thread is one block instead of the same conversation repeated
                // down the feed.
                final threads = widget.group
                    ? groupFeed(posts)
                    : [
                        for (final post in posts)
                          FeedThread(root: post, replies: const []),
                      ];

                return [
                  if (widget.allowFilter &&
                      (filtering || value.posts.length >= _searchAfter))
                    filter,
                  SliverList.builder(
                    itemCount: threads.length,
                    itemBuilder: (context, index) => _Thread(
                      threads[index],
                      showTopBorder: index > 0 || widget.header != null,
                      measureKey:
                          threads[index].root.unread == true &&
                              !_sent.contains(threads[index].root.id)
                          ? _unread.putIfAbsent(
                              threads[index].root.id,
                              GlobalKey.new,
                            )
                          : null,
                    ),
                  ),
                  // Fetching more mid-filter would look like the filter had broken.
                  if (!filtering)
                    SliverToBoxAdapter(child: _Footer(value, notifier)),
                ];
              }(),
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
          ],
        ),
      ),
    );
  }
}

/// One feed entry: a post, and the page's own replies to it beneath.
class _Thread extends StatelessWidget {
  const _Thread(this.thread, {required this.showTopBorder, this.measureKey});

  final FeedThread thread;
  final bool showTopBorder;

  /// Set while the root of this entry is unread, so the list can measure it — and
  /// carries the accent rail that says so.
  final GlobalKey? measureKey;

  @override
  Widget build(BuildContext context) {
    final body = _body(context);
    if (measureKey == null) return body;
    // `.unread-dot` — the same hairline rail the activity feeds use, so unread means
    // one thing across the app.
    return Container(
      key: measureKey,
      decoration: BoxDecoration(
        border: Border(
          left: BorderSide(color: context.palette.accent, width: 2),
        ),
      ),
      child: body,
    );
  }

  Widget _body(BuildContext context) {
    if (!thread.isThread) {
      return PostTile(thread.root, showTopBorder: showTopBorder);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        PostTile(
          thread.root,
          showTopBorder: showTopBorder,
          // Its replies are right below it, so quoting the parent it answers is
          // still useful — but only for the root, not for every reply in the tree.
        ),
        Padding(
          padding: const EdgeInsets.only(bottom: space4),
          // No rootId: this tree is only what the page returned, so "read more"
          // opens the thread rather than trying to load into a feed.
          child: ReplyBranch(thread.replies),
        ),
      ],
    );
  }
}

class _Footer extends StatelessWidget {
  const _Footer(this.state, this.notifier);

  final FeedState state;
  final FeedNotifier notifier;

  @override
  Widget build(BuildContext context) {
    if (state.loadMoreError != null) {
      return StatusMessage(
        messageFor(state.loadMoreError!),
        onRetry: () => notifier.loadMore(asked: true),
      );
    }
    if (state.hasMore) return const Spinner();
    return const SizedBox(height: space6);
  }
}

/// Filters what is already loaded. Nothing is fetched, which is the point: it is
/// instant, and it works on the posts you can actually see.
class _Filter extends StatelessWidget {
  const _Filter(this.controller, this.onChanged);

  final TextEditingController controller;
  final VoidCallback onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: gutterOf(context),
        vertical: space3,
      ),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.soft)),
      ),
      child: Row(
        children: [
          Text('/', style: theme.bodySmall!.copyWith(color: palette.accent)),
          const SizedBox(width: space3),
          Expanded(
            child: TextField(
              controller: controller,
              onChanged: (_) => onChanged(),
              style: theme.bodySmall,
              cursorColor: palette.accent,
              decoration: InputDecoration(
                isDense: true,
                border: InputBorder.none,
                contentPadding: EdgeInsets.zero,
                hintText: 'filter these posts',
                hintStyle: theme.bodySmall!.copyWith(color: palette.muted),
              ),
            ),
          ),
          if (controller.text.isNotEmpty)
            GestureDetector(
              onTap: () {
                controller.clear();
                onChanged();
              },
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.only(left: space3),
                child: Text('clear', style: theme.labelSmall!.asLink(palette)),
              ),
            ),
        ],
      ),
    );
  }
}
