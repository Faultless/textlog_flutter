import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/models.dart';
import '../../state/cache.dart';
import '../../state/feed.dart';
import '../../state/providers.dart';
import '../../state/relationships.dart';
import '../../state/session.dart';
import '../screens/web_action.dart';
import '../theme.dart';
import 'compose_sheet.dart';
import 'form_parts.dart';
import 'glyph.dart';
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
        // Room for a thumb; the glyph inside stays small.
        padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
        child: Glyph(Glyphs.more.$2, Glyphs.more.$1),
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
    if (context.mounted) toast(context, failure.message);
  }
}

/// The server's list, from `api-write.tsx`. `bot` is new.
const _reasons = ['harassment', 'spam', 'impersonation', 'bot', 'other'];

Future<void> _report(BuildContext context, WidgetRef ref, Post post) async {
  final palette = context.palette;
  final theme = Theme.of(context).textTheme;

  final reason = await showModalBottomSheet<String>(
    context: context,
    backgroundColor: Colors.transparent,
    // Without these the sheet is capped at half the screen and clips whatever does
    // not fit — which the fifth reason did, and a sixth certainly would.
    isScrollControlled: true,
    constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
    builder: (context) => Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(top: BorderSide(color: palette.soft)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
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
                    padding: const EdgeInsets.symmetric(vertical: space4),
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
    if (context.mounted) toast(context, 'Reported. Thank you.');
  } on ApiFailure catch (failure) {
    if (context.mounted) toast(context, failure.message);
  }
}

void toast(BuildContext context, String message) {
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
///
/// The state comes from your own following list rather than from the profile, which
/// does not carry it. Until that list has answered, the button says `follow …` — it
/// would rather admit it does not know than tell you the wrong thing.
class FollowButton extends ConsumerStatefulWidget {
  const FollowButton(this.handle, {super.key});

  final String handle;

  @override
  ConsumerState<FollowButton> createState() => _FollowButtonState();
}

class _FollowButtonState extends ConsumerState<FollowButton> {
  /// Set once we have acted, so the button never flickers back while the list catches up.
  bool? _pending;
  var _busy = false;

  Future<void> _toggle(bool following) async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null || _busy) return;
    final next = !following;

    setState(() {
      _busy = true;
      _pending = next;
    });
    // Optimistic, and shared: every control showing this account agrees at once.
    ref.read(relationshipsProvider.notifier).noteFollow(widget.handle, following: next);
    try {
      await ref.read(apiProvider).follow(session.token, widget.handle, following: next);
    } on ApiFailure catch (failure) {
      ref.read(relationshipsProvider.notifier).noteFollow(widget.handle, following: following);
      if (mounted) {
        setState(() => _pending = following);
        toast(context, failure.message);
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionProvider).valueOrNull;
    if (session == null || session.account.handle == widget.handle) return const SizedBox.shrink();

    final known = _pending ?? ref.watch(followsProvider(widget.handle));
    final following = known ?? false;
    return TextlogButton(
      // The arrow is the site's "this does something" marker, and it is held back
      // until the answer is actually known — so a button that is about to say
      // `unfollow` never first claims the opposite in the same words.
      following ? 'unfollow' : (known == null ? 'follow' : 'follow →'),
      tone: following ? ButtonTone.unfollow : ButtonTone.primary,
      // Following twice is idempotent on the server, so the tap works either way.
      onPressed: _busy ? null : () => _toggle(following),
    );
  }
}

/// `block` / `unblock`, which the site keeps well away from `follow`.
///
/// Blocking is destructive enough to confirm, and it drops the follow with it — the
/// server does that, so the local sets do too.
class BlockAction extends ConsumerWidget {
  const BlockAction(this.handle, {super.key, this.style, this.onChanged});

  final String handle;
  final TextStyle? style;

  /// Called after a successful change, so a block list can drop the row in place.
  final void Function(bool blocked)? onChanged;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = style ?? Theme.of(context).textTheme.bodySmall!;
    final session = ref.watch(sessionProvider).valueOrNull;
    if (session == null || session.account.handle == handle) return const SizedBox.shrink();

    final blocked = ref.watch(blocksProvider(handle)) ?? false;

    return Pressable(
      onTap: () async {
        if (!blocked && !await _confirmBlock(context, handle)) return;
        ref.read(relationshipsProvider.notifier).noteBlock(handle, blocked: !blocked);
        try {
          await ref.read(apiProvider).block(session.token, handle, blocked: !blocked);
          onChanged?.call(!blocked);
        } on ApiFailure catch (failure) {
          ref.read(relationshipsProvider.notifier).noteBlock(handle, blocked: blocked);
          if (context.mounted) toast(context, failure.message);
        }
      },
      builder: (context, pressed) => Text(
        blocked ? 'unblock' : 'block',
        style: theme.asLink(palette).copyWith(
          color: pressed ? palette.accent : (blocked ? palette.muted : palette.errorInk),
        ),
      ),
    );
  }
}

Future<bool> _confirmBlock(BuildContext context, String handle) async {
  final palette = context.palette;
  final theme = Theme.of(context).textTheme;

  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      backgroundColor: palette.panel,
      shape: const RoundedRectangleBorder(),
      title: Text('Block @$handle', style: theme.bodyMedium),
      content: Text(
        'You will not see their posts and they will not see yours. '
        'If you follow them, that ends too.',
        style: theme.bodySmall!.copyWith(color: palette.quoteInk, height: 1.55),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text('cancel', style: theme.bodySmall!.copyWith(color: palette.muted)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text('block', style: theme.bodySmall!.copyWith(color: palette.errorInk)),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}
