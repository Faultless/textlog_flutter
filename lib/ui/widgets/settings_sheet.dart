import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/settings.dart';
import '../theme.dart';

/// A bottom sheet rather than a screen: appearance is a two-tap decision, and it
/// should not take you out of what you were reading.
Future<void> showSettings(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: context.palette.panel,
  shape: const RoundedRectangleBorder(),
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

    return SafeArea(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('appearance', style: theme.bodySmall!.copyWith(color: palette.muted)),
            const SizedBox(height: space4),
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
            Text('accent', style: theme.bodySmall!.copyWith(color: palette.muted)),
            const SizedBox(height: space4),
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
          ],
        ),
      ),
    );
  }
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
          color: selected ? palette.accent : palette.tagBg,
          border: Border.all(color: selected ? palette.accent : palette.soft),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.bodySmall!.copyWith(
            color: selected ? palette.bg : palette.ink,
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
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: colour,
            shape: BoxShape.circle,
            border: Border.all(
              color: selected ? palette.ink : palette.soft,
              width: selected ? 2 : 1,
            ),
          ),
          child: choice == AccentChoice.theme
              ? Icon(Icons.auto_awesome, size: 12, color: palette.bg)
              : null,
        ),
      ),
    );
  }
}
