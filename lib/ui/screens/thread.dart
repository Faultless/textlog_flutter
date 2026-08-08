import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feed_source.dart';
import '../../state/providers.dart';
import '../widgets/feed_view.dart';
import '../widgets/post_tile.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';

class ThreadScreen extends ConsumerWidget {
  const ThreadScreen({super.key, required this.id});

  final int id;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final post = ref.watch(postProvider(id));

    return Scaffold(
      appBar: textlogAppBar(context, path: '/post/$id', showBack: true),
      body: switch (post) {
        AsyncData(:final value) => FeedView(
          RepliesFeed(id),
          header: SliverToBoxAdapter(child: PostTile(value, showTopBorder: false)),
          emptyMessage: 'No replies yet.',
        ),
        AsyncError(:final error) => StatusMessage(
          messageFor(error),
          onRetry: () => ref.invalidate(postProvider(id)),
        ),
        _ => const Spinner(),
      },
    );
  }
}
