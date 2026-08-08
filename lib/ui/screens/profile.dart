import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feed_source.dart';
import '../../core/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/feed_view.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.handle});

  final String handle;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(handle));

    return Scaffold(
      appBar: textlogAppBar(context, path: '/u/$handle', showBack: true),
      body: FeedView(
        UserFeed(handle),
        emptyMessage: 'No posts yet.',
        header: SliverToBoxAdapter(
          child: switch (profile) {
            AsyncData(:final value) => _Header(value),
            AsyncError(:final error) => StatusMessage(messageFor(error)),
            _ => const Spinner(),
          },
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.profile);

  final Profile profile;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('@${profile.handle}', style: theme.titleLarge),
          if (profile.bio.trim().isNotEmpty) ...[
            const SizedBox(height: space3),
            // Bios routinely contain ASCII art, so preserve the author's spacing.
            Text(profile.bio, style: theme.bodyMedium!.copyWith(color: palette.quoteInk)),
          ],
          const SizedBox(height: space4),
          Text(
            '${profile.postCount} posts · ${profile.followerCount} followers · '
            '${profile.followingCount} following',
            style: theme.labelSmall,
          ),
        ],
      ),
    );
  }
}
