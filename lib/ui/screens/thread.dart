import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/reply_tree.dart';
import '../../state/cache.dart';
import '../../state/providers.dart';
import '../../state/thread.dart';
import '../theme.dart';
import '../widgets/post_tile.dart';
import '../widgets/pressable.dart';
import '../widgets/reply_tree.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';

/// A thread: the post it is about, then its replies.
///
/// `flat` and `tree` are the site's own toggle. On a phone the nesting rail eats
/// horizontal space fast, so a deep thread read sideways is a real problem — flat
/// mode drops the indentation and reads the conversation in order instead.
class ThreadScreen extends ConsumerWidget {
  const ThreadScreen({super.key, required this.id, this.flat = false});

  final int id;
  final bool flat;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(id));
    final replies = ref.watch(threadProvider(id));
    final palette = context.palette;

    return Scaffold(
      appBar: textlogAppBar(context, path: '/post/$id', showBack: true),
      body: RefreshIndicator(
        color: palette.accent,
        backgroundColor: palette.panel,
        onRefresh: () async {
          ref.read(postCacheProvider).forget(id);
          ref.invalidate(postProvider(id));
          // Not invalidate: the notifier refetches only what has aged out and keeps
          // the rest, which is the difference between one request and sixteen.
          await ref.read(threadProvider(id).notifier).refresh();
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            switch (post) {
              AsyncData(:final value) => PostTile(
                value,
                showTopBorder: false,
                large: true,
                isSubject: true,
              ),
              AsyncError(:final error) => StatusMessage(
                messageFor(error),
                onRetry: () => ref.invalidate(postProvider(id)),
              ),
              _ => const Spinner(),
            },
            switch (replies) {
              AsyncData(:final value) when value.isEmpty => const StatusMessage(
                'No replies yet.',
              ),
              AsyncData(:final value) => Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _RepliesHeader(id: id, nodes: value, flat: flat),
                  Padding(
                    padding: const EdgeInsets.only(bottom: space6),
                    child: flat
                        ? FlatReplies(value, rootId: id)
                        : ReplyBranch(value, rootId: id),
                  ),
                ],
              ),
              AsyncError(:final error) => StatusMessage(
                messageFor(error),
                onRetry: () => ref.invalidate(threadProvider(id)),
              ),
              _ => const Spinner(),
            },
          ],
        ),
      ),
    );
  }
}

/// `N replies` on the left, the `flat` / `tree` toggle on the right.
class _RepliesHeader extends StatelessWidget {
  const _RepliesHeader({required this.id, required this.nodes, required this.flat});

  final int id;
  final List<ReplyNode> nodes;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final shown = countReplies(nodes);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space3),
      decoration: BoxDecoration(
        border: Border(
          top: BorderSide(color: palette.soft),
          bottom: BorderSide(color: palette.soft),
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              '$shown ${shown == 1 ? 'reply' : 'replies'}',
              style: theme.labelSmall,
            ),
          ),
          for (final (label, isFlat) in [('tree', false), ('flat', true)])
            Padding(
              padding: const EdgeInsets.only(left: space3),
              child: Pressable(
                onTap: flat == isFlat
                    ? null
                    : () => context.go('/post/$id${isFlat ? '?view=flat' : ''}'),
                builder: (context, pressed) => Text(
                  label,
                  style: flat == isFlat
                      ? theme.labelSmall!.copyWith(color: palette.ink)
                      : theme.labelSmall!.asLink(palette).copyWith(
                          color: pressed ? palette.accent : null,
                        ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
