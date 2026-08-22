import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/feed_source.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/feed_view.dart';
import '../../state/people.dart';
import '../widgets/people_list.dart';
import '../widgets/pressable.dart';
import '../widgets/shell.dart';

/// A hashtag's notes, under a header with its counts.
///
/// `/api/v1/tags/{tag}` is new — the app used to show a bare `#tag` heading because
/// there was nothing else to show.
class TagScreen extends ConsumerWidget {
  const TagScreen({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final details = ref.watch(tagProvider(tag));

    return Scaffold(
      appBar: textlogAppBar(context, path: '/tag/$tag', showBack: true),
      body: FeedView(
        TagFeed(tag),
        emptyMessage: 'Nothing tagged #$tag yet.',
        header: SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text.rich(
                  TextSpan(
                    children: [
                      TextSpan(text: '#', style: TextStyle(color: palette.accent)),
                      TextSpan(text: tag),
                    ],
                  ),
                  style: theme.titleLarge,
                ),
                // A tag whose details fail to load is not worth an error: the notes
                // below are the page.
                if (details.valueOrNull case final value?) ...[
                  const SizedBox(height: space3),
                  Row(
                    children: [
                      Text(
                        '${value.postCount} ${value.postCount == 1 ? 'note' : 'notes'} · ',
                        style: theme.labelSmall,
                      ),
                      Pressable(
                        onTap: value.followerCount == 0
                            ? null
                            : () => context.push('/tag/$tag/followers'),
                        builder: (context, pressed) => Text(
                          '${value.followerCount} '
                          '${value.followerCount == 1 ? 'follower' : 'followers'}',
                          style: value.followerCount == 0
                              ? theme.labelSmall
                              : theme.labelSmall!.asLink(palette).copyWith(
                                  color: pressed ? palette.accent : null,
                                ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Who follows a hashtag.
class TagFollowersScreen extends StatelessWidget {
  const TagFollowersScreen({super.key, required this.tag});

  final String tag;

  @override
  Widget build(BuildContext context) => Scaffold(
    appBar: textlogAppBar(context, path: '/tag/$tag', showBack: true),
    body: Column(
      children: [
        Padding(
          padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space4),
          child: Row(
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '#', style: TextStyle(color: context.palette.accent)),
                    TextSpan(text: '$tag followers'),
                  ],
                ),
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
        Expanded(
          child: PeopleList(
            PeopleSource.tagFollowers(tag),
            emptyMessage: 'Nobody follows #$tag yet.',
          ),
        ),
      ],
    ),
  );
}
