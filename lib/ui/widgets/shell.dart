import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../theme.dart';

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
            TextSpan(text: '>_ ', style: TextStyle(color: context.palette.accent)),
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
            icon: Icon(Icons.arrow_back, size: 18, color: palette.ink),
            onPressed: () => context.canPop() ? context.pop() : context.go('/'),
          )
        : null,
    automaticallyImplyLeading: false,
    title: const Brand(),
    actions: [
      IconButton(
        tooltip: 'open on textlog.cc',
        icon: Icon(Icons.open_in_new, size: 16, color: palette.muted),
        onPressed: () => launchUrl(
          Uri.parse('$textlogOrigin${path ?? '/'}'),
          mode: LaunchMode.externalApplication,
        ),
      ),
      SizedBox(width: gutterOf(context) - space2),
    ],
  );
}

/// `.feed-tabs` — muted labels, the active one inked with a 2px accent underline.
class FeedTabs extends StatelessWidget {
  const FeedTabs({super.key, required this.tabs, required this.active, required this.onSelect});

  final List<String> tabs;
  final int active;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final style = Theme.of(context).textTheme.bodySmall!;

    return Container(
      padding: EdgeInsets.fromLTRB(gutterOf(context) - space3, space4, 0, 0),
      decoration: BoxDecoration(border: Border(bottom: BorderSide(color: palette.soft))),
      child: Row(
        children: [
          for (final (index, label) in tabs.indexed)
            GestureDetector(
              onTap: () => onSelect(index),
              behavior: HitTestBehavior.opaque,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
                decoration: BoxDecoration(
                  border: Border(
                    bottom: BorderSide(
                      width: 2,
                      color: index == active ? palette.accent : Colors.transparent,
                    ),
                  ),
                ),
                child: Text(
                  label,
                  style: style.copyWith(
                    color: index == active ? palette.ink : palette.muted,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
