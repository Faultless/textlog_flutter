import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feed_source.dart';
import '../../core/models.dart';
import '../../state/people.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../theme.dart';
import '../widgets/bio_sheet.dart';
import '../widgets/feed_view.dart';
import '../widgets/people_list.dart';
import '../widgets/post_actions.dart';
import '../widgets/post_body.dart';
import '../widgets/pressable.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';
import 'web_action.dart';

/// The tabs the site puts on a profile. `tags` is ours: the server exposes the
/// hashtags an account follows and the site only shows the count, but on a phone that
/// list is a genuinely useful way to find your way around.
enum ProfileTab {
  notes('notes'),
  replies('replies'),
  following('following'),
  followers('followers'),
  tags('tags'),
  blocked('blocked');

  const ProfileTab(this.label);
  final String label;

  /// The block list is yours alone — the server returns 403 for anybody else's.
  bool get selfOnly => this == ProfileTab.blocked;

  static ProfileTab fromName(String? name) =>
      values.where((tab) => tab.name == name).firstOrNull ?? ProfileTab.notes;
}

class ProfileScreen extends ConsumerWidget {
  const ProfileScreen({
    super.key,
    required this.handle,
    this.isSelf = false,
    this.tab = ProfileTab.notes,
  });

  final String handle;
  final bool isSelf;
  final ProfileTab tab;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profile = ref.watch(profileProvider(handle));
    final mine = ref.watch(viewerHandleProvider) == handle;
    final tabs = ProfileTab.values.where((entry) => mine || !entry.selfOnly).toList();
    final active = tabs.contains(tab) ? tab : ProfileTab.notes;

    final header = switch (profile) {
      AsyncData(:final value) => _Header(value, isSelf: mine),
      // A profile that failed is the whole page for the reader — a name, a bio and
      // every tab beneath it — so it gets a way back rather than a dead end.
      AsyncError(:final error) => StatusMessage(
        messageFor(error),
        onRetry: () => ref.refresh(profileProvider(handle).future),
      ),
      _ => const Spinner(),
    };

    return Scaffold(
      appBar: textlogAppBar(context, path: '/u/$handle', showBack: !isSelf),
      body: ReadingColumn(
        child: Column(
          children: [
            // The header scrolls with the notes tab, where it reads as part of the
            // page, and is pinned above the lists, where a header that scrolled away
            // with a list of a thousand followers would be a nuisance.
            if (active != ProfileTab.notes) header,
            FeedTabs(
              tabs: [for (final entry in tabs) TabSpec(entry.label, entry.name)],
              active: tabs.indexOf(active),
              onSelect: (index) => context.go(
                '/u/$handle${tabs[index] == ProfileTab.notes ? '' : '?tab=${tabs[index].name}'}',
              ),
            ),
            Expanded(child: _pane(active, header)),
          ],
        ),
      ),
    );
  }

  Widget _pane(ProfileTab tab, Widget header) => switch (tab) {
    ProfileTab.notes => FeedView(
      NotesFeed(handle),
      emptyMessage: 'No notes yet.',
      header: SliverToBoxAdapter(child: header),
    ),
    ProfileTab.replies => FeedView(
      UserRepliesFeed(handle),
      emptyMessage: 'No replies yet.',
    ),
    ProfileTab.following => PeopleList(
      PeopleSource.following(handle),
      emptyMessage: 'Not following anyone yet.',
    ),
    ProfileTab.followers => PeopleList(
      PeopleSource.followers(handle),
      emptyMessage: 'No followers yet.',
    ),
    ProfileTab.tags => FollowedTagsList(handle),
    ProfileTab.blocked => PeopleList(
      PeopleSource.blocks(handle),
      emptyMessage: 'You have not blocked anyone.',
      unblockable: true,
    ),
  };
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
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '@', style: TextStyle(color: palette.accent)),
                      TextSpan(text: profile.handle),
                    ],
                  ),
                  style: theme.titleLarge,
                ),
              ),
              if (isSelf)
                Wrap(
                  spacing: space2,
                  children: [
                    Pressable(
                      onTap: () => showBioSheet(context),
                      builder: (context, pressed) => Text(
                        'edit bio',
                        style: theme.bodySmall!.asLink(palette).copyWith(
                          color: pressed ? palette.accent : null,
                        ),
                      ),
                    ),
                    Pressable(
                      onTap: () => openAccount(ref),
                      builder: (context, pressed) => Text(
                        'account',
                        style: theme.bodySmall!.asLink(palette).copyWith(
                          color: pressed ? palette.accent : null,
                        ),
                      ),
                    ),
                  ],
                )
              else
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    FollowButton(profile.handle),
                    const SizedBox(height: space2),
                    BlockAction(profile.handle, style: theme.labelSmall!),
                  ],
                ),
            ],
          ),
          const SizedBox(height: space3),
          // The site linkifies a bio, and bios are full of @mentions, #hashtags and
          // links — rendering it as flat text threw all of that away.
          if (profile.bio.trim().isEmpty)
            Text(
              'No bio yet.',
              style: theme.bodyMedium!.copyWith(color: palette.quoteInk),
            )
          else
            PostBody(
              profile.bio,
              quiet: true,
              style: theme.bodyMedium!.copyWith(color: palette.quoteInk),
            ),
          const SizedBox(height: space4),
          // Every one of these numbers is a field the profile endpoint gained; the
          // app was showing a single `following` alias for two different counts.
          Wrap(
            spacing: space3,
            runSpacing: space1,
            children: [
              _Count(profile.postCount, 'note', 'notes'),
              _Count(profile.repliesCount, 'reply', 'replies'),
              _Count(profile.followingUserCount, 'following', 'following'),
              _Count(profile.followerCount, 'follower', 'followers'),
              _Count(profile.followingTagCount, 'hashtag', 'hashtags'),
              if (profile.blockedUserCount case final blocked?)
                _Count(blocked, 'blocked', 'blocked'),
            ],
          ),
        ],
      ),
    );
  }
}

class _Count extends StatelessWidget {
  const _Count(this.value, this.one, this.many);

  final int value;
  final String one;
  final String many;

  @override
  Widget build(BuildContext context) => Text(
    '$value ${value == 1 ? one : many}',
    style: Theme.of(context).textTheme.labelSmall,
  );
}
