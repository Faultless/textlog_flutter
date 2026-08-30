import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/body_analysis.dart';
import '../../core/body_tokens.dart';
import '../../core/execution.dart';
import '../../core/highlight.dart';
import '../../core/markdown.dart';
import '../../core/models.dart';
import '../../state/settings.dart';
import '../router.dart';
import '../theme.dart';

/// Renders a post body the way textlog.cc renders one: URLs, @mentions, #hashtags,
/// inline and fenced code, TeX, markdown links, strikethrough and spoilers — plus the
/// block-level markdown the site leaves flat, when that setting is on.
///
/// Stateful only because tap recognizers need disposing.
class PostBody extends ConsumerStatefulWidget {
  const PostBody(this.body, {super.key, this.style, this.quiet = false});

  final String body;

  /// Defaults to `.post p`; the quoted parent passes its smaller, quieter style.
  final TextStyle? style;

  /// A quoted parent: same content, less contrast, no poll.
  final bool quiet;

  @override
  ConsumerState<PostBody> createState() => _PostBodyState();
}

class _PostBodyState extends ConsumerState<PostBody> {
  final _recognizers = <TapGestureRecognizer>[];
  var _revealed = false;

  /// Redactions the reader has asked to see, by their text. Two identical redactions
  /// in one body reveal together, which is the reading anyone would expect.
  final _shown = <String>{};

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

  @override
  Widget build(BuildContext context) {
    _disposeRecognizers();

    final palette = context.palette;
    final plain = widget.style ?? Theme.of(context).textTheme.bodyMedium!;
    // Never run the opt-in markdown over ASCII art. Beyond the spacing, art is full
    // of `_`, `*` and `~`, which the emphasis rules would happily eat out of a drawing.
    final wanted = ref.watch(settingsProvider).valueOrNull?.markdown ?? false;

    // One pass over the body, kept: this runs on every frame a tile scrolls through.
    final analysis = analyseBody(widget.body, extended: wanted);
    // `.post p.ascii-art { line-height: 1.15 }`
    final base = analysis.asciiArt ? plain.copyWith(height: 1.15) : plain;

    final visible = _Rendered(
      analysis.visible,
      base: base,
      onTap: _onTap,
      quiet: widget.quiet,
      shown: _shown,
      onReveal: (text) => setState(() => _shown.add(text)),
    );
    if (!analysis.spoiler.hasSpoiler) return visible;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        visible,
        const SizedBox(height: space2),
        if (_revealed)
          _Rendered(
            analysis.hidden,
            base: base,
            onTap: _onTap,
            quiet: widget.quiet,
            shown: _shown,
            onReveal: (text) => setState(() => _shown.add(text)),
          )
        else
          // `<details><summary>reveal</summary>` — the reader opts in.
          GestureDetector(
            onTap: () => setState(() => _revealed = true),
            behavior: HitTestBehavior.opaque,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
              decoration: BoxDecoration(border: Border.all(color: palette.soft)),
              child: Text('reveal', style: base.asLink(palette)),
            ),
          ),
      ],
    );
  }
}

/// One run of body text, split into blocks and drawn.
class _Rendered extends StatelessWidget {
  const _Rendered(
    this.blocks, {
    required this.base,
    required this.onTap,
    required this.quiet,
    required this.shown,
    required this.onReveal,
  });

  final List<BodyBlock> blocks;
  final TextStyle base;
  final TapGestureRecognizer Function(VoidCallback) onTap;
  final bool quiet;

  /// Redactions already revealed, and how to reveal another.
  final Set<String> shown;
  final void Function(String text) onReveal;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;

    if (blocks.length == 1 && blocks.first is ParagraphBlock) {
      return _paragraph(context, blocks.first as ParagraphBlock, palette);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (index, block) in blocks.indexed) ...[
          if (index > 0) SizedBox(height: _gapBefore(block)),
          _block(context, block, palette),
        ],
      ],
    );
  }

  double _gapBefore(BodyBlock block) => switch (block) {
    ListItemBlock() => space1,
    HeadingBlock() => space3,
    RuleBlock() => space3,
    _ => space2,
  };

  Widget _block(BuildContext context, BodyBlock block, Palette palette) => switch (block) {
    ParagraphBlock() => _paragraph(context, block, palette),
    HeadingBlock(:final level, :final spans) => _text(
      context,
      spans,
      base.copyWith(
        fontSize: base.fontSize! * switch (level) { 1 => 1.35, 2 => 1.18, 3 => 1.06, _ => 1.0 },
        fontWeight: FontWeight.w700,
        fontVariations: const [FontVariation.weight(700)],
        height: 1.35,
      ),
      palette,
    ),
    ListItemBlock(:final indent, :final spans, :final ordinal, :final checked) => Padding(
      padding: EdgeInsets.only(left: space2 + indent * space4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            switch ((ordinal, checked)) {
              (_, true) => '[x] ',
              (_, false) => '[ ] ',
              (final number?, _) => '$number. ',
              _ => '• ',
            },
            style: base.copyWith(color: palette.muted),
          ),
          Expanded(child: _text(context, spans, base, palette)),
        ],
      ),
    ),
    QuoteBlock(:final blocks) => Container(
      padding: const EdgeInsets.only(left: space3),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: palette.soft, width: 2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (final inner in blocks)
            _block(context, inner, palette),
        ],
      ),
    ),
    CodeBlock(:final text, :final language) => _Scrollable(
      fill: true,
      child: Container(
        padding: const EdgeInsets.all(space3),
        color: palette.tagBg,
        child: Text.rich(
          _highlighted(text, language, base, palette),
          style: base.copyWith(height: 1.35, color: palette.ink),
        ),
      ),
    ),
    MathBlock(:final tex) => _Scrollable(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: space2),
        child: _Tex(tex, style: base, display: true),
      ),
    ),
    RuleBlock() => Container(
      height: 1,
      margin: const EdgeInsets.symmetric(vertical: space2),
      color: palette.soft,
    ),
    TableBlock() => _Scrollable(child: _table(context, block, palette)),
  };

  Widget _paragraph(BuildContext context, ParagraphBlock block, Palette palette) =>
      _text(context, block.spans, base, palette);

  /// A `js` or `python` fence, coloured the way the site colours it. Any other
  /// language comes back as one run, so this costs a fence nothing.
  TextSpan _highlighted(
    String text,
    String? language,
    TextStyle base,
    Palette palette,
  ) => TextSpan(
    children: [
      for (final span in highlightCode(text, language: language))
        TextSpan(
          text: span.text,
          style: switch (span.kind) {
            CodeToken.plain => null,
            CodeToken.keyword => TextStyle(color: palette.accentDark),
            CodeToken.comment => TextStyle(color: palette.muted),
            // Strings and numbers share a colour on the site too.
            CodeToken.string || CodeToken.number => TextStyle(color: palette.selfInk),
          },
        ),
    ],
  );

  Widget _table(BuildContext context, TableBlock block, Palette palette) {
    TextAlign align(int column) => switch (
      column < block.alignments.length ? block.alignments[column] : TextAlignment.start
    ) {
      TextAlignment.start => TextAlign.start,
      TextAlignment.center => TextAlign.center,
      TextAlignment.end => TextAlign.end,
    };

    Widget cell(List<BodyToken> spans, int column, {required bool header}) => Padding(
      padding: const EdgeInsets.symmetric(horizontal: space3, vertical: space2),
      child: _text(
        context,
        spans,
        header
            ? base.copyWith(
                fontWeight: FontWeight.w700,
                fontVariations: const [FontVariation.weight(700)],
              )
            : base,
        palette,
        align: align(column),
      ),
    );

    return Table(
      defaultColumnWidth: const IntrinsicColumnWidth(),
      border: TableBorder.all(color: palette.soft),
      children: [
        TableRow(
          decoration: BoxDecoration(color: palette.tagBg),
          children: [
            for (final (column, spans) in block.header.indexed)
              cell(spans, column, header: true),
          ],
        ),
        for (final row in block.rows)
          TableRow(
            children: [
              for (var column = 0; column < block.header.length; column++)
                cell(column < row.length ? row[column] : const [], column, header: false),
            ],
          ),
      ],
    );
  }

  Widget _text(
    BuildContext context,
    List<BodyToken> spans,
    TextStyle style,
    Palette palette, {
    TextAlign align = TextAlign.start,
  }) {
    // Inline TeX has to be a widget, so a run containing any needs WidgetSpans.
    return Text.rich(
      TextSpan(
        children: [
          for (final token in spans) _span(context, token, style, palette),
        ],
        style: style,
      ),
      textAlign: align,
    );
  }

  InlineSpan _span(
    BuildContext context,
    BodyToken token,
    TextStyle base,
    Palette palette,
  ) {
    final link = base.asLink(palette);
    return switch (token) {
      PlainText(:final text) => TextSpan(text: text),
      StyledText(
        :final text,
        :final bold,
        :final italic,
        :final strike,
        :final underline,
        :final redacted,
        :final code,
      ) =>
        () {
          // `|x|` — a bar the width of the words under it, until it is pressed. Ink
          // on ink rather than an empty box, so the line does not reflow on reveal.
          final hidden = redacted && !shown.contains(text);
          return TextSpan(
            text: text,
            recognizer: hidden ? onTap(() => onReveal(text)) : null,
            style: base.copyWith(
              fontWeight: bold ? FontWeight.w700 : null,
              fontVariations: bold ? const [FontVariation.weight(700)] : null,
              fontStyle: italic ? FontStyle.italic : null,
              // Several can apply at once, so they combine rather than one winning.
              decoration: TextDecoration.combine([
                if (strike) TextDecoration.lineThrough,
                if (underline) TextDecoration.underline,
              ]),
              decorationColor: underline ? palette.ink : null,
              // `<code>` — a tinted run rather than a box, so it can wrap mid-line.
              backgroundColor: hidden
                  ? palette.ink
                  : redacted
                  ? palette.tagBg
                  : code
                  ? palette.tagBg
                  : null,
              color: hidden ? palette.ink : (code || redacted ? palette.ink : null),
            ),
          );
        }(),
      MathToken(:final tex) => WidgetSpan(
        alignment: PlaceholderAlignment.middle,
        child: _Tex(tex, style: base, display: false),
      ),
      LinkToken(:final url, :final text) => _linkSpan(context, url, text, base, link),
      MentionToken(:final handle) => TextSpan(
        text: '@$handle',
        style: link,
        recognizer: onTap(() => context.push('/u/${handle.toLowerCase()}')),
      ),
      TagToken(:final tag) => TextSpan(
        text: '#$tag',
        style: link,
        recognizer: onTap(() => context.push('/tag/${tag.toLowerCase()}')),
      ),
    };
  }

  /// The site keeps a link's host whole and lets only its path break, so a long URL
  /// wraps without pushing the column wider. Two spans, one recognizer each.
  InlineSpan _linkSpan(
    BuildContext context,
    String url,
    String text,
    TextStyle base,
    TextStyle link,
  ) {
    void open() => openLink(context, url);

    final split = linkBreakPoint(text);
    if (split >= text.length) {
      return TextSpan(text: text, style: link, recognizer: onTap(open));
    }
    return TextSpan(
      children: [
        TextSpan(text: text.substring(0, split), recognizer: onTap(open)),
        TextSpan(text: text.substring(split), recognizer: onTap(open)),
      ],
      style: link,
    );
  }
}

/// TeX, rendered as widgets. Falls back to the source in a code run when the
/// expression does not parse — which is what the site does when MathJax refuses it.
class _Tex extends StatelessWidget {
  const _Tex(this.tex, {required this.style, required this.display});

  final String tex;
  final TextStyle style;
  final bool display;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Math.tex(
      tex,
      textStyle: style.copyWith(fontFamily: null, fontFamilyFallback: null),
      mathStyle: display ? MathStyle.display : MathStyle.text,
      onErrorFallback: (_) => Text(
        tex,
        style: style.copyWith(backgroundColor: palette.tagBg),
      ),
    );
  }
}

/// What a `#exec` post printed, under the code that printed it.
///
/// The server ran the fence once, when the post was written, and stored the output;
/// nothing executes on this device and every reader sees the same characters. Drawn
/// like a code fence because that is what it is — output, monospaced, scrolled
/// sideways rather than wrapped, and cut to the same ten lines the site shows.
class ExecutionOutput extends StatelessWidget {
  const ExecutionOutput(this.post, {super.key});

  final Post post;

  @override
  Widget build(BuildContext context) {
    if (!hasExecutionOutput(post.executionOutput)) return const SizedBox.shrink();
    final palette = context.palette;
    final base = Theme.of(context).textTheme.bodyMedium!;

    return Padding(
      padding: const EdgeInsets.only(top: space3),
      child: _Scrollable(
        fill: true,
        child: Container(
          padding: const EdgeInsets.all(space3),
          decoration: BoxDecoration(
            color: palette.tagBg,
            border: Border(left: BorderSide(color: palette.accent, width: 2)),
          ),
          child: Text(
            displayedExecutionOutput(post.executionOutput!),
            // The line height code art needs: output is often a drawing, and the
            // default leading pulls a box apart into stripes.
            style: base.copyWith(height: 1.15, color: palette.ink),
          ),
        ),
      ),
    );
  }
}

/// Code, tables and display maths can all be wider than the column. Scroll them
/// inside their own box rather than letting the page scroll sideways.
class _Scrollable extends StatelessWidget {
  const _Scrollable({required this.child, this.fill = false});

  final Widget child;

  /// Grow a narrow child out to the column, so a code block's tint spans the width
  /// the way it does on the site. It cannot ask for that itself: inside a sideways
  /// viewport the width is unbounded, and `double.infinity` there takes the page
  /// down with it — which is what a single short code fence used to do.
  final bool fill;

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: fill && constraints.hasBoundedWidth
          ? ConstrainedBox(
              constraints: BoxConstraints(minWidth: constraints.maxWidth),
              child: child,
            )
          : child,
    ),
  );
}
