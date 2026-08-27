import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/notification_plan.dart';
import '../../state/notifications.dart';
import '../../state/session.dart';
import '../../state/settings.dart';
import '../theme.dart';
import 'post_actions.dart';
import 'glyph.dart';
import 'pressable.dart';

/// A bottom sheet rather than a screen: appearance is a two-tap decision, and it
/// should not take you out of what you were reading.
///
/// The sheet paints its own background instead of passing `backgroundColor`, which
/// is captured once at call time and would keep the old colour when you switch
/// theme with the sheet still open.
Future<void> showSettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  // Without these the sheet is capped at half the screen and simply clips whatever
  // does not fit, leaving settings below the fold unreachable rather than scrollable.
  isScrollControlled: true,
  constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.85),
  builder: (_) => const _Settings(),
);

class _Settings extends ConsumerWidget {
  const _Settings();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? const Settings();
    final notifier = ref.read(settingsProvider.notifier);
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(top: BorderSide(color: palette.soft)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const _Handle(),
            Padding(
              padding: EdgeInsets.fromLTRB(gutterOf(context), 0, space2, 0),
              child: Row(
                children: [
                  Expanded(child: Text('appearance', style: theme.titleLarge)),
                  IconButton(
                    tooltip: 'done',
                    visualDensity: VisualDensity.compact,
                    icon: Glyph(Glyphs.close.$2, Glyphs.close.$1, size: 18),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            // The handle and title stay put; only the settings scroll.
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(
                  gutterOf(context),
                  space4,
                  gutterOf(context),
                  space5,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                  _Label('theme'),
                  const SizedBox(height: space3),
                  Wrap(
                    spacing: space2,
                    runSpacing: space2,
                    children: [
                      for (final choice in ThemeChoice.values)
                        _Chip(
                          label: choice.id,
                          selected: settings.theme == choice,
                          onTap: () => notifier.setTheme(choice),
                        ),
                    ],
                  ),
                  const SizedBox(height: space5),
                  _Label('accent'),
                  const SizedBox(height: space3),
                  Wrap(
                    spacing: space3,
                    runSpacing: space3,
                    children: [
                      for (final choice in AccentChoice.values)
                        _Swatch(
                          choice: choice,
                          selected: settings.accent == choice,
                          onTap: () => notifier.setAccent(choice),
                        ),
                    ],
                  ),
                  const SizedBox(height: space5),
                  _Label('font'),
                  const SizedBox(height: space3),
                  Wrap(
                    spacing: space2,
                    runSpacing: space2,
                    children: [
                      for (final choice in FontChoice.values)
                        _Chip(
                          label: choice.label,
                          selected: settings.font == choice,
                          onTap: () => notifier.setFont(choice),
                        ),
                    ],
                  ),
                  const SizedBox(height: space3),
                  // The one thing that visibly separates them, shown in the face itself.
                  Text(
                    '┌──┐ != >= -> ~~ 0O1l',
                    style: theme.bodySmall!.copyWith(color: palette.quoteInk),
                  ),
                  const SizedBox(height: space5),
                  _Label('text size'),
                  const SizedBox(height: space3),
                  Wrap(
                    spacing: space2,
                    runSpacing: space2,
                    children: [
                      for (final choice in TextSize.values)
                        _Chip(
                          label: choice.id,
                          selected: settings.textSize == choice,
                          onTap: () => notifier.setTextSize(choice),
                        ),
                    ],
                  ),
                  const SizedBox(height: space5),
                  _Label('reading'),
                  const SizedBox(height: space2),
                  _Toggle(
                    title: 'render markdown',
                    // Say what the trade-off is rather than leaving people to wonder
                    // why a post looks different here than on the site. Code, TeX,
                    // links and strikethrough are not part of this — the site does
                    // those, so the app always does too.
                    note: 'headings, lists and tables, which textlog.cc keeps flat',
                    value: settings.markdown,
                    onChanged: notifier.setMarkdown,
                  ),
                  const SizedBox(height: space4),
                  _Toggle(
                    title: 'offer translations',
                    // Says where the translation comes from, because "translate" on
                    // a phone usually means a request to somebody's cloud.
                    note: 'when textlog finds a post is not in English',
                    value: settings.translate,
                    onChanged: notifier.setTranslate,
                  ),
                  const SizedBox(height: space4),
                  _Toggle(
                    title: 'barebones',
                    note: 'characters instead of icons, no ripples, no animation',
                    value: settings.barebones,
                    onChanged: notifier.setBarebones,
                  ),
                  if (ref.watch(notifySupportedProvider)) ...[
                    const SizedBox(height: space5),
                    _Label('notifications'),
                    const SizedBox(height: space2),
                    const _Notifications(),
                  ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Replies, mentions and follows, and the honest note about how they arrive.
class _Notifications extends ConsumerWidget {
  const _Notifications();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final signedIn = ref.watch(viewerProvider) != null;
    final preferences = ref.watch(notifyProvider).valueOrNull ?? NotifyPreferences.off;
    final notifier = ref.read(notifyProvider.notifier);

    if (!signedIn) {
      return Text(
        'Sign in to be told about replies and mentions.',
        style: theme.labelSmall!.copyWith(color: palette.muted, height: 1.5),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Toggle(
          title: 'notify me',
          // Say what it actually does. textlog has no push endpoint an app can
          // reach, so this is a background check rather than instant delivery.
          // Fifteen minutes is Android's floor for periodic work and it batches
          // further while the phone is idle, so "at least" is the honest word.
          note: 'checked in the background, at least 15 minutes apart',
          value: preferences.enabled,
          onChanged: (wanted) async {
            final granted = await notifier.setEnabled(wanted);
            if (!granted && wanted && context.mounted) {
              toast(context, 'Notifications are turned off for textlog in system settings.');
            }
          },
        ),
        if (preferences.enabled)
          for (final kind in NotifyKind.values) ...[
            const SizedBox(height: space3),
            Padding(
              padding: const EdgeInsets.only(left: space4),
              child: _Toggle(
                title: kind.id,
                note: kind.description,
                value: preferences.kinds.contains(kind),
                onChanged: (wanted) => notifier.toggleKind(kind, wanted),
              ),
            ),
          ],
      ],
    );
  }
}

/// Grab bar — the affordance that says this can be dragged away.
class _Handle extends StatelessWidget {
  const _Handle();

  @override
  Widget build(BuildContext context) => Center(
    child: Container(
      width: 36,
      height: context.chrome.plain ? 1 : 4,
      margin: const EdgeInsets.symmetric(vertical: space3),
      decoration: BoxDecoration(
        color: context.palette.soft,
        // A rounded pill is a Material affordance; barebones gets a rule.
        borderRadius: context.chrome.plain ? null : BorderRadius.circular(2),
      ),
    ),
  );
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: Theme.of(context).textTheme.labelSmall!.copyWith(color: context.palette.muted),
  );
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.selected, required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme.bodySmall!;

    // Barebones: a filled pill is exactly the sort of thing this mode exists to
    // remove, so selection is shown the way a terminal would show it.
    if (context.chrome.plain) {
      return Pressable(
        onTap: onTap,
        hitPadding: const EdgeInsets.symmetric(horizontal: space2, vertical: space3),
        builder: (context, pressed) => Text(
          selected ? '[*] $label' : '[ ] $label',
          style: theme.copyWith(
            color: pressed
                ? palette.accent
                : selected
                ? palette.ink
                : palette.muted,
          ),
        ),
      );
    }

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
        decoration: BoxDecoration(
          color: selected ? palette.accent : palette.bg,
          border: Border.all(color: selected ? palette.accent : palette.soft),
        ),
        child: Text(
          label,
          style: theme.copyWith(color: selected ? palette.bg : palette.muted),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.choice, required this.selected, required this.onTap});

  final AccentChoice choice;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    // `theme` means "whatever this palette already uses", so show that.
    final colour = choice.forBrightness(palette.brightness) ?? palette.accent;
    final plain = context.chrome.plain;

    return Semantics(
      label: choice.id,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            // Barebones squares everything off; a circle is a shape the site never
            // draws.
            shape: plain ? BoxShape.rectangle : BoxShape.circle,
            // A ring rather than a thicker border, so the swatch colour does not
            // change size when you pick it.
            border: Border.all(
              color: selected ? palette.ink : palette.soft,
              width: selected ? 2 : 1,
            ),
          ),
          child: Center(
            child: Container(
              width: selected ? 18 : 22,
              height: selected ? 18 : 22,
              decoration: BoxDecoration(
                color: colour,
                shape: plain ? BoxShape.rectangle : BoxShape.circle,
              ),
            ),
          ),
        ),
      ),
    );
  }
}


class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.title,
    required this.note,
    required this.value,
    required this.onChanged,
  });

  final String title;
  final String note;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return GestureDetector(
      onTap: () => onChanged(!value),
      behavior: HitTestBehavior.opaque,
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: theme.bodySmall),
                const SizedBox(height: space1),
                Text(note, style: theme.labelSmall!.copyWith(color: palette.muted)),
              ],
            ),
          ),
          PlainCheck(value: value, onChanged: onChanged),
        ],
      ),
    );
  }
}

