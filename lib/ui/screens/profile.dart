import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/feed_source.dart';
import '../../core/models.dart';
import '../../state/identity.dart';
import '../../state/session.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/feed_view.dart';
import '../widgets/shell.dart';
import '../widgets/post_actions.dart';
import '../widgets/status.dart';
import 'web_action.dart';

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({super.key, required this.handle, this.isSelf = false});

  final String handle;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(handle));

    return Scaffold(
      appBar: textlogAppBar(context, path: '/u/$handle', showBack: !isSelf),
      body: FeedView(
        NotesFeed(handle),
        emptyMessage: 'No posts yet.',
        header: SliverToBoxAdapter(
          child: switch (profile) {
            AsyncData(:final value) => _Header(value, isSelf: isSelf),
            AsyncError(:final error) => StatusMessage(messageFor(error)),
            _ => const Spinner(),
          },
        ),
      ),
    );
  }
}

class _Header extends ConsumerWidget {
  const _Header(this.profile, {required this.isSelf});

  final Profile profile;
  final bool isSelf;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(
                        text: '@',
                        style: TextStyle(color: palette.accent),
                      ),
                      TextSpan(text: profile.handle),
                    ],
                  ),
                  style: theme.titleLarge,
                ),
              ),
              if (isSelf) ...[
                GestureDetector(
                  onTap: () => openAccount(ref),
                  child: Text('account', style: theme.bodySmall!.asLink(palette)),
                ),
                const SizedBox(width: space4),
                GestureDetector(
                  onTap: () => _confirmSignOut(context, ref),
                  child: Text('log out', style: theme.bodySmall!.asLink(palette)),
                ),
              ] else
                FollowButton(profile.handle),
            ],
          ),
          const SizedBox(height: space3),
          // Bios routinely contain ASCII art, so preserve the author's spacing.
          Text(
            profile.bio.trim().isEmpty ? 'No bio yet.' : profile.bio,
            style: theme.bodyMedium!.copyWith(color: palette.quoteInk),
          ),
          const SizedBox(height: space4),
          Text(
            '${profile.postCount} notes · ${profile.followingUserCount} following · '
            '${profile.followerCount} ${profile.followerCount == 1 ? 'follower' : 'followers'}',
            style: theme.labelSmall,
          ),
        ],
      ),
    );
  }
}

/// Signs the app out and forgets the handle. A browser session on textlog.cc is a
/// separate thing, so say so rather than implying this ends both.
Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
  final palette = context.palette;
  final theme = Theme.of(context).textTheme;

  final signOut = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: palette.panel,
      shape: const RoundedRectangleBorder(),
      title: Text('Log out', style: theme.bodyMedium),
      content: Text(
        'This signs the app out and forgets your handle.\n\n'
        'A browser session on textlog.cc stays signed in. End that from account '
        'settings if you want to log out everywhere.',
        style: theme.bodySmall!.copyWith(color: palette.quoteInk, height: 1.55),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('cancel', style: theme.bodySmall!.copyWith(color: palette.muted)),
        ),
        TextButton(
          onPressed: () {
            Navigator.pop(context, false);
            openSessions(ref);
          },
          child: Text('browser sessions', style: theme.bodySmall!.copyWith(color: palette.accent)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('forget', style: theme.bodySmall!.copyWith(color: palette.errorInk)),
        ),
      ],
    ),
  );

  if (signOut ?? false) {
    await ref.read(sessionProvider.notifier).signOut();
    await ref.read(identityProvider.notifier).forget();
  }
}
