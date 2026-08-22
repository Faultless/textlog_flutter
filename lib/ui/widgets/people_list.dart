import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../state/people.dart';
import '../theme.dart';
import 'post_actions.dart';
import 'post_meta.dart';
import 'pressable.dart';
import 'status.dart';

/// `followers`, `following` and `blocked` — one list, keyed by which.
///
/// The relationship endpoints return `{handle, url}` and nothing else, so a row is a
/// handle and the action that belongs next to it. Fetching a profile per row to show
/// a bio would be a request per row, which is exactly the trade this app does not make.
class PeopleList extends ConsumerStatefulWidget {
  const PeopleList(this.source, {super.key, required this.emptyMessage, this.unblockable = false});

  final PeopleSource source;
  final String emptyMessage;

  /// A block list offers `unblock` and drops the row when it succeeds.
  final bool unblockable;

  @override
  ConsumerState<PeopleList> createState() => _PeopleListState();
}

const _loadMoreThreshold = 400.0;

class _PeopleListState extends ConsumerState<PeopleList> {
  final _controller = ScrollController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      final position = _controller.position;
      if (position.pixels >= position.maxScrollExtent - _loadMoreThreshold) {
        ref.read(peopleProvider(widget.source).notifier).loadMore();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(peopleProvider(widget.source));
    final notifier = ref.read(peopleProvider(widget.source).notifier);

    return RefreshIndicator(
      onRefresh: notifier.refresh,
      color: context.palette.accent,
      backgroundColor: context.palette.panel,
      child: CustomScrollView(
        controller: _controller,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: switch (people) {
          AsyncData(:final value) when value.items.isEmpty => [
            SliverToBoxAdapter(child: StatusMessage(widget.emptyMessage)),
          ],
          AsyncData(:final value) => [
            SliverList.builder(
              itemCount: value.items.length,
              itemBuilder: (context, index) => _Row(
                value.items[index],
                showTopBorder: index > 0,
                unblockable: widget.unblockable,
                onUnblocked: () => notifier.removeLocal(value.items[index].handle),
              ),
            ),
            SliverToBoxAdapter(
              child: switch (value) {
                PeopleState(:final loadMoreError?) => StatusMessage(
                  messageFor(loadMoreError),
                  onRetry: () => notifier.loadMore(asked: true),
                ),
                PeopleState(hasMore: true) => const Spinner(),
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

class _Row extends StatelessWidget {
  const _Row(
    this.person, {
    required this.showTopBorder,
    required this.unblockable,
    required this.onUnblocked,
  });

  final UserRef person;
  final bool showTopBorder;
  final bool unblockable;
  final VoidCallback onUnblocked;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = Theme.of(context).textTheme.bodySmall!;

    return InkWell(
      onTap: () => context.push('/u/${person.handle}'),
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space4),
        decoration: BoxDecoration(
          border: Border(
            top: showTopBorder ? BorderSide(color: palette.soft) : BorderSide.none,
          ),
        ),
        child: Row(
          children: [
            Expanded(child: HandleLink(person.handle, style: meta)),
            if (unblockable)
              BlockAction(
                person.handle,
                style: meta,
                onChanged: (blocked) {
                  if (!blocked) onUnblocked();
                },
              )
            else
              FollowButton(person.handle),
          ],
        ),
      ),
    );
  }
}

/// The hashtags an account follows. Same shape, different rows.
class FollowedTagsList extends ConsumerWidget {
  const FollowedTagsList(this.handle, {super.key});

  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tags = ref.watch(followedTagsProvider(handle));
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return switch (tags) {
      AsyncData(:final value) when value.items.isEmpty => const StatusMessage(
        'No hashtags followed yet.',
      ),
      AsyncData(:final value) => ListView.builder(
        itemCount: value.items.length,
        itemBuilder: (context, index) {
          final tag = value.items[index];
          return InkWell(
            onTap: () => context.push('/tag/${tag.tag}'),
            child: Container(
              padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space4),
              decoration: BoxDecoration(
                border: Border(
                  top: index > 0 ? BorderSide(color: palette.soft) : BorderSide.none,
                ),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Pressable(
                      onTap: () => context.push('/tag/${tag.tag}'),
                      builder: (context, pressed) => Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(text: '#', style: TextStyle(color: palette.accent)),
                            TextSpan(text: tag.tag),
                          ],
                        ),
                        style: theme.bodySmall!.asLink(palette).copyWith(
                          color: pressed ? palette.accent : palette.ink,
                        ),
                      ),
                    ),
                  ),
                  Text(
                    '${tag.postCount} ${tag.postCount == 1 ? 'note' : 'notes'}',
                    style: theme.labelSmall,
                  ),
                ],
              ),
            ),
          );
        },
      ),
      AsyncError(:final error) => StatusMessage(
        messageFor(error),
        onRetry: () => ref.invalidate(followedTagsProvider(handle)),
      ),
      _ => const Spinner(),
    };
  }
}
