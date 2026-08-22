import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../state/cache.dart';
import '../../state/feed.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../screens/web_action.dart';
import '../theme.dart';
import 'compose_sheet.dart';
import 'form_parts.dart';
import 'pressable.dart';

/// `reply`, plus a menu holding whatever else this post allows: `edit` and `delete`
/// on your own, `report` on other people's. Returned as loose widgets so they sit on
/// the same line as the handle and time, the way `.posttop` does on the site.
///
/// Without a session these fall back to opening textlog.cc, so the app still works
/// against a server that has no write endpoints.
List<Widget> postActions(
  BuildContext context,
  WidgetRef ref,
  Post post, {
  TextStyle? style,
  bool isSubject = false,
}) {
  final palette = context.palette;
  final meta = style ?? Theme.of(context).textTheme.bodySmall!;
  final session = ref.watch(sessionProvider).valueOrNull;
  final mine = session != null && session.account.handle == post.author.handle;

  return [
    Pressable(
      onTap: () async {
        if (session == null) {
          await openReply(ref, post.id);
          return;
        }
        await showCompose(context, kind: ComposeKind.reply, target: post);
      },
      builder: (context, pressed) => Text(
        // The site says `continue` when you are replying to yourself, and says so
        // before you have signed in rather than offering an action that cannot work.
        session == null
            ? 'sign in to reply'
            : mine
            ? 'continue'
            : 'reply',
        style: meta.asLink(palette).copyWith(color: pressed ? palette.accent : palette.muted),
      ),
    ),
    const Spacer(),
    if (mine)
      PostMenu(
        style: meta,
        entries: [
          MenuEntry('edit', () => showCompose(context, kind: ComposeKind.edit, target: post)),
          MenuEntry(
            'delete',
            () => _confirmDelete(context, ref, post, isSubject: isSubject),
            colour: palette.errorInk,
          ),
        ],
      )
    else if (session != null)
      PostMenu(
        style: meta,
        entries: [MenuEntry('report', () => _report(context, ref, post))],
      ),
  ];
}

final class MenuEntry {
  const MenuEntry(this.label, this.onSelected, {this.colour});

  final String label;
  final VoidCallback onSelected;
  final Color? colour;
}

/// The overflow. Everything but `reply` lives here, so a post's meta line stays one
/// line instead of wrapping a red `delete` onto the next one.
class PostMenu extends StatelessWidget {
  const PostMenu({super.key, required this.entries, this.style});

  final List<MenuEntry> entries;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final meta = style ?? Theme.of(context).textTheme.bodySmall!;

    return PopupMenuButton<MenuEntry>(
      tooltip: 'more actions',
      color: palette.panel,
      elevation: 3,
      position: PopupMenuPosition.under,
      padding: EdgeInsets.zero,
      splashRadius: 0,
      shape: RoundedRectangleBorder(side: BorderSide(color: palette.soft)),
      onSelected: (entry) => entry.onSelected(),
      itemBuilder: (context) => [
        for (final entry in entries)
          PopupMenuItem(
            value: entry,
            height: 36,
            child: Text(entry.label, style: meta.copyWith(color: entry.colour ?? palette.ink)),
          ),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: space2, vertical: space1),
        child: Icon(Icons.more_horiz, size: 16, color: palette.muted),
      ),
    );
  }
}

Future<void> _confirmDelete(
  BuildContext context,
  WidgetRef ref,
  Post post, {
  required bool isSubject,
}) async {
  final palette = context.palette;
  final theme = Theme.of(context).textTheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: palette.panel,
      shape: const RoundedRectangleBorder(),
      title: Text('Delete this post', style: theme.bodyMedium),
      content: Text(
        'It will read "(deleted)" and cannot be brought back.',
        style: theme.bodySmall!.copyWith(color: palette.quoteInk, height: 1.55),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('cancel', style: theme.bodySmall!.copyWith(color: palette.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('delete', style: theme.bodySmall!.copyWith(color: palette.errorInk)),
        ),
      ],
    ),
  );
  if (confirmed != true) return;

  final session = ref.read(sessionProvider).valueOrNull;
  if (session == null) return;
  try {
    await ref.read(apiProvider).deletePost(session.token, post.id);

    // The server has already agreed, so drop it from view now rather than leaving a
    // post on screen that no longer exists until something refetches.
    ref.read(postCacheProvider).forget(post.id);
    ref.read(repliesCacheProvider).apply(post.id, null);
    applyToLiveFeeds(post.id, null);
    // The note count sits right next to the list it no longer agrees with.
    ref.invalidate(profileProvider(post.author.handle));
    if (post.parentId case final parent?) {
      ref.read(postCacheProvider).forget(parent);
      ref.invalidate(postProvider(parent));
    }
    // Only leave when the page was about this post. Deleting from a feed or a
    // profile should leave you where you were, with the post simply gone.
    if (isSubject && context.mounted) {
      final parent = post.parentId;
      parent == null ? context.go('/') : context.go('/post/$parent');
    }
  } on ApiFailure catch (failure) {
    if (context.mounted) _toast(context, failure.message);
  }
}

const _reasons = ['harassment', 'spam', 'impersonation', 'other'];

Future<void> _report(BuildContext context, WidgetRef ref, Post post) async {
  final palette = context.palette;
  final theme = Theme.of(context).textTheme;

  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(top: BorderSide(color: palette.soft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('report @${post.author.handle}', style: theme.titleLarge),
              const SizedBox(height: space4),
              for (final value in _reasons)
                GestureDetector(
                  onTap: () => Navigator.pop(context, value),
                  behavior: HitTestBehavior.opaque,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: space3),
                    child: Text(value, style: theme.bodyMedium!.asLink(palette)),
                  ),
                ),
              const SizedBox(height: space3),
            ],
          ),
        ),
      ),
    ),
  );
  if (reason == null) return;

  final session = ref.read(sessionProvider).valueOrNull;
  if (session == null) return;
  try {
    await ref.read(apiProvider).report(session.token, post.id, reason);
    if (context.mounted) _toast(context, 'Reported. Thank you.');
  } on ApiFailure catch (failure) {
    if (context.mounted) _toast(context, failure.message);
  }
}

void _toast(BuildContext context, String message) {
  final palette = context.palette;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      backgroundColor: palette.panel,
      behavior: SnackBarBehavior.floating,
      shape: const RoundedRectangleBorder(),
      content: Text(
        message,
        style: Theme.of(context).textTheme.bodySmall!.copyWith(color: palette.ink),
      ),
    ),
  );
}

/// `.button` / `.button.unfollow-button` on a profile.
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton(this.handle, {super.key});

  final String handle;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  bool? _following;
  var _busy = false;

  Future<void> _toggle() async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null || _busy) return;
    final next = !(_following ?? false);

    setState(() {
      _busy = true;
      _following = next;
    });
    try {
      await ref.read(apiProvider).follow(session.token, widget.handle, following: next);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() => _following = !next);
        _toast(context, failure.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).valueOrNull;
    if (session == null || session.account.handle == widget.handle) return const SizedBox.shrink();

    final following = _following ?? false;
    return TextlogButton(
      following ? 'unfollow' : 'follow →',
      tone: following ? ButtonTone.unfollow : ButtonTone.primary,
      onPressed: _busy ? null : _toggle,
    );
  }
}
