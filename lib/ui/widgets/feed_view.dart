import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feed_source.dart';
import '../../state/feed.dart';
import '../theme.dart';
import 'post_tile.dart';
import 'status.dart';

/// The whole reading experience: give it a [FeedSource] and it paginates, refreshes
/// and recovers on its own. [header] is an optional sliver pinned above the posts.
class FeedView extends ConsumerStatefulWidget {
  const FeedView(this.source, {super.key, this.header, this.emptyMessage = 'Nothing here yet.'});

  final FeedSource source;
  final Widget? header;
  final String emptyMessage;

  @override
  ConsumerState<FeedView> createState() => _FeedViewState();
}

const _loadMoreThreshold = 600.0;

class _FeedViewState extends ConsumerState<FeedView> {
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
      ref.read(feedProvider(widget.source).notifier).loadMore();
    }
  }

  @override
  Widget build(BuildContext context) {
    final feed = ref.watch(feedProvider(widget.source));
    final notifier = ref.read(feedProvider(widget.source).notifier);

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      color: context.palette.accent,
      backgroundColor: context.palette.panel,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          if (widget.header != null) widget.header!,
          ...switch (feed) {
            AsyncData(:final value) when value.posts.isEmpty => [
              SliverToBoxAdapter(child: StatusMessage(widget.emptyMessage)),
            ],
            AsyncData(:final value) => [
              SliverList.builder(
                itemCount: value.posts.length,
                itemBuilder: (context, index) => PostTile(
                  value.posts[index],
                  showTopBorder: index > 0 || widget.header != null,
                ),
              ),
              SliverToBoxAdapter(child: _Footer(value, notifier)),
            ],
            AsyncError(:final error) => [
              SliverToBoxAdapter(
                child: StatusMessage(messageFor(error), onRetry: notifier.refresh),
              ),
            ],
            _ => const [SliverToBoxAdapter(child: Spinner())],
          },
        ],
      ),
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
      return StatusMessage(messageFor(state.loadMoreError!), onRetry: notifier.loadMore);
    }
    if (state.hasMore) return const Spinner();
    return const SizedBox(height: space6);
  }
}
