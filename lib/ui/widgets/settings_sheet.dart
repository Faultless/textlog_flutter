import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings.dart';
import '../theme.dart';

/// A bottom sheet rather than a screen: appearance is a two-tap decision, and it
/// should not take you out of what you were reading.
///
/// The sheet paints its own background instead of passing `backgroundColor`, which
/// is captured once at call time and would keep the old colour when you switch
/// theme with the sheet still open.
Future<void> showSettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
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
                    icon: Icon(Icons.close, size: 18, color: palette.muted),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
            Padding(
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
                  _Label('reading'),
                  const SizedBox(height: space2),
                  _Toggle(
                    title: 'render markdown',
                    // Say what the trade-off is instead of leaving people to
                    // wonder why a post looks different here than on the site.
                    note: 'textlog.cc shows posts as plain text',
                    value: settings.markdown,
                    onChanged: notifier.setMarkdown,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
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
      height: 4,
      margin: const EdgeInsets.symmetric(vertical: space3),
      decoration: BoxDecoration(
        color: context.palette.soft,
        borderRadius: BorderRadius.circular(2),
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
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: selected ? palette.bg : palette.muted,
          ),
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

    return Semantics(
      label: choice.id,
      selected: selected,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 30,
          height: 30,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
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
              decoration: BoxDecoration(color: colour, shape: BoxShape.circle),
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
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: palette.bg,
            activeTrackColor: palette.accent,
            inactiveThumbColor: palette.muted,
            inactiveTrackColor: palette.bg,
            trackOutlineColor: WidgetStatePropertyAll(palette.soft),
          ),
        ],
      ),
    );
  }
}
