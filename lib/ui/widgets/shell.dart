import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../state/identity.dart';
import '../../state/session.dart';
import '../theme.dart';
import 'account_sheet.dart';
import '../screens/web_action.dart';
import 'compose_sheet.dart';
import 'glyph.dart';
import 'pressable.dart';
import 'settings_sheet.dart';

/// `.brand` — the wordmark, with the accent full stop.
class Brand extends StatelessWidget {
  const Brand({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge!.copyWith(letterSpacing: -1);
    return GestureDetector(
      onTap: () => context.go('/'),
      child: Text.rich(
        TextSpan(
          children: [
            // The prompt glyph from textlog.svg, drawn as type so there is no
            // SVG dependency for a two-character mark.
            TextSpan(
              text: '>_ ',
              style: TextStyle(color: context.palette.accent),
            ),
            const TextSpan(text: 'textlog'),
          ],
        ),
        style: style,
      ),
    );
  }
}

/// The site header: wordmark left, a link out to the web app right.
AppBar textlogAppBar(BuildContext context, {String? path, bool showBack = false}) {
  final palette = context.palette;
  return AppBar(
    backgroundColor: palette.bg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleSpacing: showBack ? 0 : gutterOf(context),
    leading: showBack
        ? IconButton(
            tooltip: 'back',
            icon: Glyph(Glyphs.back.$2, Glyphs.back.$1, size: 18, colour: palette.ink),
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          )
        : null,
    automaticallyImplyLeading: false,
    title: const Brand(),
    actions: [
      // Barebones has no floating button, so writing lives here — which also means
      // it is reachable from a thread or a profile rather than only from a feed.
      if (context.chrome.plain) const _WriteAction(),
      IconButton(
        tooltip: 'search',
        visualDensity: VisualDensity.compact,
        icon: Glyph(Glyphs.search.$2, Glyphs.search.$1, size: 18),
        onPressed: () => context.push('/search'),
      ),
      _You(path: path),
      IconButton(
        tooltip: 'appearance',
        visualDensity: VisualDensity.compact,
        icon: Glyph(Glyphs.appearance.$2, Glyphs.appearance.$1),
        onPressed: () => showSettings(context),
      ),
      SizedBox(width: gutterOf(context) - space3),
    ],
  );
}

/// One entry in [FeedTabs].
final class TabSpec {
  const TabSpec(this.label, this.path, {this.marked = false});

  final String label;
  final String path;

  /// An unread marker — `.unread-dot` on the site.
  final bool marked;
}

/// `.feed-tabs` — muted labels, the active one inked with a 2px accent underline.
///
/// Scrolls sideways. The site has three tabs and room for them; signed in, the app
/// has five, and on a narrow phone a row that clips is a row with unreachable tabs.
class FeedTabs extends StatefulWidget {
  const FeedTabs({
    super.key,
    required this.tabs,
    required this.active,
    required this.onSelect,
    this.trailing,
  });

  final List<TabSpec> tabs;
  final int active;
  final ValueChanged<int> onSelect;

  /// `mark all as read` and friends, pinned to the right of the row.
  final Widget? trailing;

  @override
  State<FeedTabs> createState() => _FeedTabsState();
}

class _FeedTabsState extends State<FeedTabs> {
  final _controller = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(FeedTabs old) {
    super.didUpdateWidget(old);
    // Selecting a tab that is half off screen should bring it into view.
    if (old.active != widget.active) _reveal();
  }

  void _reveal() {
    if (!_controller.hasClients) return;
    final fraction = widget.tabs.isEmpty ? 0.0 : widget.active / widget.tabs.length;
    _controller.animateTo(
      (_controller.position.maxScrollExtent * fraction).clamp(
        0.0,
        _controller.position.maxScrollExtent,
      ),
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(context).textTheme.bodySmall!;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.soft)),
      ),
      padding: EdgeInsets.only(top: space4),
      child: Row(
        children: [
          Expanded(
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              padding: EdgeInsets.only(left: gutterOf(context) - space3),
              child: Row(
                children: [
                  for (final (index, tab) in widget.tabs.indexed)
                    Semantics(
                      selected: index == widget.active,
                      button: true,
                      child: GestureDetector(
                        onTap: () => widget.onSelect(index),
                        behavior: HitTestBehavior.opaque,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: space3,
                            vertical: space2,
                          ),
                          decoration: BoxDecoration(
                            border: Border(
                              bottom: BorderSide(
                                width: 2,
                                color: index == widget.active
                                    ? palette.accent
                                    : Colors.transparent,
                              ),
                            ),
                          ),
                          child: Row(
                            children: [
                              Text(
                                tab.label,
                                style: style.copyWith(
                                  color: index == widget.active ? palette.ink : palette.muted,
                                ),
                              ),
                              if (tab.marked) ...[
                                const SizedBox(width: space2),
                                // `.unread-dot`
                                Container(
                                  width: 6,
                                  height: 6,
                                  decoration: BoxDecoration(
                                    color: palette.accent,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (widget.trailing case final trailing?)
            Padding(
              padding: EdgeInsets.only(left: space3, right: gutterOf(context), bottom: space2),
              child: trailing,
            ),
        ],
      ),
    );
  }
}

/// `+ write`, the barebones stand-in for the floating button.
class _WriteAction extends ConsumerWidget {
  const _WriteAction();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    return Pressable(
      hitPadding: const EdgeInsets.symmetric(horizontal: space2, vertical: space3),
      onTap: () async {
        if (ref.read(sessionProvider).valueOrNull == null) {
          await openCompose(ref);
          return;
        }
        await showCompose(context);
      },
      builder: (context, pressed) => Text(
        '+ write',
        style: Theme.of(context).textTheme.bodySmall!.asLink(palette).copyWith(
          color: pressed ? palette.accent : null,
        ),
      ),
    );
  }
}

/// `@handle` once you have told the app who you are, `sign in` before that.
class _You extends ConsumerWidget {
  const _You({this.path});

  /// The page on screen, so the sheet's "open on textlog.cc" lands in the same place.
  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final handle =
        ref.watch(sessionProvider).valueOrNull?.account.handle ??
        ref.watch(identityProvider).valueOrNull;
    return GestureDetector(
      onTap: () => showAccount(context, path: path),
      child: Padding(
        // Vertical room too: in the app bar this was a 16px-tall target.
        padding: const EdgeInsets.symmetric(horizontal: space2, vertical: space3),
        child: Text(
          handle == null ? 'sign in' : '@$handle',
          style: Theme.of(context).textTheme.bodySmall!.asLink(context.palette),
        ),
      ),
    );
  }
}
