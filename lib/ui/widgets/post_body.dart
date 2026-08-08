import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/body_tokens.dart';
import '../../core/markdown.dart';
import '../../state/settings.dart';
import '../theme.dart';

/// Renders a post body with the same tokens the website links: URLs, @mentions and
/// #hashtags — plus rudimentary markdown when it is switched on.
///
/// Stateful only because tap recognizers need disposing.
class PostBody extends ConsumerStatefulWidget {
  const PostBody(this.body, {super.key, this.style});

  final String body;

  /// Defaults to `.post p`; the quoted parent passes its smaller, quieter style.
  final TextStyle? style;

  @override
  ConsumerState<PostBody> createState() => _PostBodyState();
}

class _PostBodyState extends ConsumerState<PostBody> {
  final _recognizers = <TapGestureRecognizer>[];

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _disposeRecognizers() {
    for (final recognizer in _recognizers) {
      recognizer.dispose();
    }
    _recognizers.clear();
  }

  TapGestureRecognizer _onTap(VoidCallback action) {
    final recognizer = TapGestureRecognizer()..onTap = action;
    _recognizers.add(recognizer);
    return recognizer;
  }

  TextSpan _span(BodyToken token, TextStyle base, TextStyle link) => switch (token) {
    PlainText(:final text) => TextSpan(text: text),
    StyledText(:final text, :final bold, :final italic, :final strike) => TextSpan(
      text: text,
      style: base.copyWith(
        fontWeight: bold ? FontWeight.w700 : null,
        fontVariations: bold ? const [FontVariation.weight(700)] : null,
        fontStyle: italic ? FontStyle.italic : null,
        decoration: strike ? TextDecoration.lineThrough : null,
      ),
    ),
    LinkToken(:final url, :final text) => TextSpan(
      text: text,
      style: link,
      recognizer: _onTap(
        () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      ),
    ),
    MentionToken(:final handle) => TextSpan(
      text: '@$handle',
      style: link,
      recognizer: _onTap(() => context.push('/u/${handle.toLowerCase()}')),
    ),
    TagToken(:final tag) => TextSpan(
      text: '#$tag',
      style: link,
      recognizer: _onTap(() => context.push('/tag/${tag.toLowerCase()}')),
    ),
  };

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final palette = context.palette;
    final plain = widget.style ?? Theme.of(context).textTheme.bodyMedium!;
    // `.post p.ascii-art { line-height: 1.15 }`
    final base = isAsciiArt(widget.body) ? plain.copyWith(height: 1.15) : plain;
    final link = base.asLink(palette);
    // Never run markdown over ASCII art. Beyond the spacing, art is full of `_` and
    // `*`, which the emphasis rules would happily eat out of the middle of a drawing.
    final markdown =
        (ref.watch(settingsProvider).valueOrNull?.markdown ?? false) && !isAsciiArt(widget.body);

    if (!markdown) {
      return Text.rich(
        TextSpan(
          children: [
            for (final token in tokenizeBody(widget.body)) _span(token, base, link),
          ],
          style: base,
        ),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final line in markdownLines(widget.body)) _line(line, base, link, palette),
      ],
    );
  }

  Widget _line(BodyLine line, TextStyle base, TextStyle link, Palette palette) {
    final style = switch (line.kind) {
      BlockKind.heading => base.copyWith(
        fontSize: base.fontSize! * switch (line.level) { 1 => 1.35, 2 => 1.18, _ => 1.06 },
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation.weight(700)],
        height: 1.35,
      ),
      _ => base,
    };

    final text = Text.rich(
      TextSpan(
        children: [for (final token in line.spans) _span(token, style, link)],
        style: style,
      ),
    );

    return switch (line.kind) {
      BlockKind.bullet => Padding(
        padding: const EdgeInsets.only(left: space2),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('• ', style: style.copyWith(color: palette.muted)),
            Expanded(child: text),
          ],
        ),
      ),
      BlockKind.heading => Padding(
        padding: const EdgeInsets.only(top: space2, bottom: space1),
        child: text,
      ),
      BlockKind.paragraph => text,
    };
  }
}
