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

/// `.brand` — the wordmark, with the accent prompt glyph.
///
/// Drops to just `>_` when the header has no room for the whole word. That decision
/// is made by *measuring*, not by a width breakpoint: how much room is left depends
/// on how long the reader's handle is, whether barebones mode has added `+ write`,
/// and what text size they chose — a breakpoint gets all three wrong, and the
/// wordmark was being silently clipped as a result.
class Brand extends StatelessWidget {
  const Brand({super.key});

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.titleLarge!.copyWith(letterSpacing: -1);
    // The prompt glyph from textlog.svg, drawn as type so there is no SVG
    // dependency for a two-character mark.
    final caret = TextSpan(text: '>_', style: TextStyle(color: context.palette.accent));
    final mark = TextSpan(style: style, children: [caret]);
    final full = TextSpan(style: style, children: [caret, const TextSpan(text: ' textlog')]);

    return GestureDetector(
      onTap: () => context.go('/'),
      child: LayoutBuilder(
        builder: (context, constraints) => Text.rich(
          _fits(context, full, constraints.maxWidth) ? full : mark,
          maxLines: 1,
          softWrap: false,
        ),
      ),
    );
  }
}

/// Whether [span] renders inside [available] without being cut off.
bool _fits(BuildContext context, TextSpan span, double available) {
  if (!available.isFinite) return true;
  final painter = TextPainter(
    text: span,
    textDirection: Directionality.of(context),
    textScaler: MediaQuery.textScalerOf(context),
    maxLines: 1,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width <= available;
}

/// `header, main, .site-footer { max-width: 760px; width: 100%; margin: auto }`
///
/// Without this the app filled whatever width it was given, so on a laptop a post
/// body ran a thousand pixels wide and was genuinely hard to read. The site has
/// always had a measure; this is it.
class ReadingColumn extends StatelessWidget {
  const ReadingColumn({super.key, required this.child});

  final Widget child;

  static const maxWidth = 760.0;

  @override
  Widget build(BuildContext context) => Center(
    child: ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: maxWidth),
      child: child,
    ),
  );
}

/// The site header: wordmark left, the account and the controls right.
///
/// The whole row lives inside the reading column, so the wordmark lines up with the
/// posts underneath it rather than drifting to the corner of a wide window.
AppBar textlogAppBar(BuildContext context, {String? path, bool showBack = false}) {
  final palette = context.palette;
  return AppBar(
    backgroundColor: palette.bg,
    surfaceTintColor: Colors.transparent,
    elevation: 0,
    scrolledUnderElevation: 0,
    titleSpacing: 0,
    automaticallyImplyLeading: false,
    title: ReadingColumn(
      child: Row(
        children: [
          if (showBack)
            IconButton(
              tooltip: 'back',
              icon: Glyph(Glyphs.back.$2, Glyphs.back.$1, size: 18, colour: palette.ink),
              onPressed: () => context.canPop() ? context.pop() : context.go('/'),
            )
          else
            SizedBox(width: gutterOf(context)),
          // One flex child, not two. With a Spacer beside it the wordmark took half
          // the slack rather than what it needed, so a long handle clipped it while
          // dead space sat next to it. The Align is the spacer.
          const Flexible(
            child: Align(alignment: Alignment.centerLeft, child: Brand()),
          ),
          // Barebones has no floating button, so writing lives here — which also
          // means it is reachable from a thread or a profile, not only from a feed.
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
      ),
    ),
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
  ///
  /// A builder rather than a widget, because whether there is room for the long
  /// wording depends on how wide this row actually is — and the row is inside a
  /// reading column, so the window width is the wrong thing to ask.
  final Widget Function(bool compact)? trailing;

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

  /// Below this the row cannot afford a long status line beside five tabs.
  ///
  /// Measured rather than guessed: at 390px `you've seen it all` was 207px of the
  /// row, leaving the tabs 153px — four of the five off screen before you started.
  static const _roomForWords = 520.0;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(context).textTheme.bodySmall!;

    return Container(
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: palette.soft)),
      ),
      padding: EdgeInsets.only(top: space4),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final compact = constraints.maxWidth < _roomForWords;
          final trailing = widget.trailing?.call(compact);

          return Row(
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
                                      color: index == widget.active
                                          ? palette.ink
                                          : palette.muted,
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
              if (trailing != null)
                // Bounded rather than flexible. A Flexible here would compete with
                // the Expanded above and pin the tabs to half the row even when the
                // action needs a fraction of that; a ceiling lets the tabs have
                // everything the action does not actually use, and stops an
                // OS-level text scale from pushing it past the edge.
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: constraints.maxWidth * 0.4),
                  child: Padding(
                    padding: EdgeInsets.only(
                      left: space3,
                      right: gutterOf(context),
                      bottom: space2,
                    ),
                    child: trailing,
                  ),
                ),
            ],
          );
        },
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
        if (ref.read(viewerProvider) == null) {
          await openCompose(ref);
          return;
        }
        await showCompose(context);
      },
      builder: (context, pressed) => Text(
        // Just the plus once the row is tight.
        MediaQuery.sizeOf(context).width < 380 ? '+' : '+ write',
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
        ref.watch(viewerProvider)?.account.handle ??
        ref.watch(identityProvider).valueOrNull;
    return GestureDetector(
      onTap: () => showAccount(context, path: path),
      child: Padding(
        // Vertical room too: in the app bar this was a 16px-tall target.
        padding: const EdgeInsets.symmetric(horizontal: space2, vertical: space3),
        child: ConstrainedBox(
          // Handles run to 24 characters, which at this size is most of a phone's
          // header. Truncate rather than let it shove the controls off screen.
          constraints: const BoxConstraints(maxWidth: 96),
          child: Text(
            handle == null ? 'sign in' : '@$handle',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context).textTheme.bodySmall!.asLink(context.palette),
          ),
        ),
      ),
    );
  }
}
