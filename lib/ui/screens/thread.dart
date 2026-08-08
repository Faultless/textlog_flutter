import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/cache.dart';
import '../../state/providers.dart';
import '../../state/thread.dart';
import '../theme.dart';
import '../widgets/post_tile.dart';
import '../widgets/reply_tree.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';

class ThreadScreen extends ConsumerWidget {
  const ThreadScreen({super.key, required this.id});

  final int id;

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
          ref.invalidate(threadProvider(id));
          await ref.read(threadProvider(id).future);
        },
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            switch (post) {
              AsyncData(:final value) => PostTile(value, showTopBorder: false, large: true),
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
              AsyncData(:final value) => Padding(
                padding: const EdgeInsets.only(bottom: space6),
                child: ReplyBranch(value),
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
