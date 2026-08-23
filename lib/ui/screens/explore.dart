import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/post_actions.dart';
import '../widgets/post_meta.dart';
import '../widgets/pressable.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';

/// `/explore` — people and hashtags worth following.
///
/// One request returns both, which is why this is not two feeds: the endpoint pages
/// them on separate cursors and the app shows the first page of each. Somewhere to
/// start from, rather than a directory to page through.
class ExploreScreen extends ConsumerWidget {
  const ExploreScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final explore = ref.watch(exploreProvider);

    return Scaffold(
      appBar: textlogAppBar(context, path: '/explore', showBack: true),
      body: ReadingColumn(
        child: RefreshIndicator(
          onRefresh: () async => ref.invalidate(exploreProvider),
          color: context.palette.accent,
          backgroundColor: context.palette.panel,
          child: switch (explore) {
            AsyncData(:final value) => _Lists(value),
            AsyncError(:final error) => ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                StatusMessage(
                  messageFor(error),
                  onRetry: () => ref.invalidate(exploreProvider),
                ),
              ],
            ),
            _ => const Spinner(),
          },
        ),
      ),
    );
  }
}

class _Lists extends StatelessWidget {
  const _Lists(this.explore);

  final Explore explore;

  @override
  Widget build(BuildContext context) {
    if (explore.people.isEmpty && explore.tags.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [StatusMessage('Nothing to suggest just yet.')],
      );
    }

    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      children: [
        if (explore.people.isNotEmpty) ...[
          const _Heading('people'),
          for (final (index, person) in explore.people.indexed)
            _Person(person, showTopBorder: index > 0),
        ],
        if (explore.tags.isNotEmpty) ...[
          const _Heading('hashtags'),
          for (final (index, tag) in explore.tags.indexed)
            _Tag(tag, showTopBorder: index > 0),
        ],
        const SizedBox(height: space6),
      ],
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.label);

  final String label;

  @override
  Widget build(BuildContext context) => Container(
    width: double.infinity,
    padding: EdgeInsets.fromLTRB(gutterOf(context), space5, gutterOf(context), space3),
    decoration: BoxDecoration(
      border: Border(bottom: BorderSide(color: context.palette.soft)),
    ),
    child: Text(
      label,
      style: Theme.of(context).textTheme.labelSmall!.copyWith(
        color: context.palette.muted,
      ),
    ),
  );
}

class _Person extends StatelessWidget {
  const _Person(this.person, {required this.showTopBorder});

  final UserRef person;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context) {
    final meta = Theme.of(context).textTheme.bodySmall!;
    return _Row(
      showTopBorder: showTopBorder,
      onTap: () => context.push('/u/${person.handle}'),
      child: Row(
        children: [
          Expanded(child: HandleLink(person.handle, style: meta)),
          FollowButton(person.handle),
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.tag, {required this.showTopBorder});

  final TagDetails tag;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return _Row(
      showTopBorder: showTopBorder,
      onTap: () => context.push('/tag/${tag.tag}'),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Pressable(
                  hitPadding: const EdgeInsets.symmetric(vertical: space1),
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
                Text(
                  '${tag.postCount} ${tag.postCount == 1 ? 'note' : 'notes'} · '
                  '${tag.followerCount} '
                  '${tag.followerCount == 1 ? 'follower' : 'followers'}',
                  style: theme.labelSmall,
                ),
              ],
            ),
          ),
          FollowTagButton(tag.tag),
        ],
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row({required this.child, required this.onTap, required this.showTopBorder});

  final Widget child;
  final VoidCallback onTap;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onTap,
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space4),
      decoration: BoxDecoration(
        border: Border(
          top: showTopBorder
              ? BorderSide(color: context.palette.soft)
              : BorderSide.none,
        ),
      ),
      child: child,
    ),
  );
}
