import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/body_tokens.dart';
import '../../core/models.dart';
import '../../state/drafts.dart';
import '../theme.dart';
import '../widgets/compose_sheet.dart';
import '../widgets/post_actions.dart';
import '../widgets/post_body.dart';
import '../widgets/pressable.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';

/// `/drafts` — what you started and did not post.
///
/// Server side, so a draft begun on the website is here and one begun here is there.
/// Opening one puts it back in the compose sheet; posting it publishes the draft
/// rather than creating a copy beside it.
class DraftsScreen extends ConsumerWidget {
  const DraftsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final drafts = ref.watch(draftsProvider);

    return Scaffold(
      appBar: textlogAppBar(context, path: '/drafts', showBack: true),
      body: ReadingColumn(
        child: RefreshIndicator(
          onRefresh: ref.read(draftsProvider.notifier).refresh,
          color: context.palette.accent,
          backgroundColor: context.palette.panel,
          child: switch (drafts) {
            AsyncData(:final value) when value.isEmpty => const _Empty(),
            AsyncData(:final value) => ListView.builder(
              physics: const AlwaysScrollableScrollPhysics(),
              itemCount: value.length,
              itemBuilder: (context, index) =>
                  _DraftTile(value[index], showTopBorder: index > 0),
            ),
            AsyncError(:final error) => StatusMessage(
              messageFor(error),
              onRetry: () => ref.refresh(draftsProvider.future),
            ),
            _ => const Spinner(),
          },
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) => ListView(
    physics: const AlwaysScrollableScrollPhysics(),
    children: const [
      StatusMessage('Nothing saved. A post you are not ready to send lands here.'),
    ],
  );
}

class _DraftTile extends ConsumerWidget {
  const _DraftTile(this.draft, {required this.showTopBorder});

  final Draft draft;
  final bool showTopBorder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return InkWell(
      onTap: () => showCompose(
        context,
        kind: draft.isReply ? ComposeKind.reply : ComposeKind.post,
        target: draft.parent,
        draft: draft,
      ),
      child: Container(
        width: double.infinity,
        padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
        decoration: BoxDecoration(
          border: Border(
            top: showTopBorder ? BorderSide(color: palette.soft) : BorderSide.none,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  draft.isReply
                      ? 'reply to @${draft.parent?.author.handle ?? 'a post'}'
                      : 'note',
                  style: theme.labelSmall!.copyWith(color: palette.muted),
                ),
                const SizedBox(width: space2),
                Text(
                  'edited ${relativeTime(draft.updatedAt)}',
                  style: theme.labelSmall!.copyWith(color: palette.muted),
                ),
              ],
            ),
            const SizedBox(height: space3),
            PostBody(draft.body),
            const SizedBox(height: space3),
            Row(
              children: [
                Pressable(
                  onTap: () => _publish(context, ref),
                  builder: (context, pressed) => Text(
                    'post →',
                    style: theme.bodySmall!.asLink(palette).copyWith(
                      color: pressed ? palette.accent : null,
                    ),
                  ),
                ),
                const Spacer(),
                Pressable(
                  onTap: () => _discard(context, ref),
                  builder: (context, pressed) => Text(
                    'discard',
                    style: theme.bodySmall!.asLink(palette).copyWith(
                      color: pressed ? palette.accent : palette.errorInk,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _publish(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(draftsProvider.notifier).publish(draft.id);
      if (context.mounted) toast(context, 'Posted.');
    } on ApiFailure catch (failure) {
      if (context.mounted) toast(context, failure.message);
    }
  }

  Future<void> _discard(BuildContext context, WidgetRef ref) async {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: palette.panel,
        shape: const RoundedRectangleBorder(),
        title: Text('Discard this draft', style: theme.bodyMedium),
        content: Text(
          'It cannot be brought back.',
          style: theme.bodySmall!.copyWith(color: palette.quoteInk, height: 1.55),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text('cancel', style: theme.bodySmall!.copyWith(color: palette.muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text('discard', style: theme.bodySmall!.copyWith(color: palette.errorInk)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      await ref.read(draftsProvider.notifier).discard(draft.id);
    } on ApiFailure catch (failure) {
      if (context.mounted) toast(context, failure.message);
    }
  }
}
