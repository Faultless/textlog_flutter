/// The block layer above [tokenizeBody].
///
/// Two levels, deliberately:
///
/// * **Always on** — fenced code blocks and display `$$…$$` maths. textlog.cc
///   renders both, so leaving them out would show the reader something the author
///   did not write.
/// * **Behind the `markdown` setting** — headings, emphasis, lists, task lists,
///   blockquotes, tables and rules. The site does *not* render these in a post body,
///   so they are opt-in: on means the app shows structure textlog.cc keeps flat.
///
/// Nothing here touches Flutter, so all of it is unit tested against strings.
library;

import 'body_tokens.dart';

sealed class BodyBlock {
  const BodyBlock();
}

/// A run of body text. Newlines inside it are significant — the site renders bodies
/// `white-space: pre-wrap`, and ASCII art depends on it.
final class ParagraphBlock extends BodyBlock {
  const ParagraphBlock(this.spans);
  final List<BodyToken> spans;
}

final class HeadingBlock extends BodyBlock {
  const HeadingBlock(this.level, this.spans);

  /// 1–6.
  final int level;
  final List<BodyToken> spans;
}

/// One list item. Nesting is by [indent] rather than by containment, which keeps the
/// parser flat and matches how a 280-character post is actually written.
final class ListItemBlock extends BodyBlock {
  const ListItemBlock({
    required this.indent,
    required this.spans,
    this.ordinal,
    this.checked,
  });

  /// Depth, counted in levels rather than spaces.
  final int indent;
  final List<BodyToken> spans;

  /// Set for an ordered item; null for a bullet.
  final int? ordinal;

  /// Set for `- [ ]` / `- [x]`.
  final bool? checked;
}

final class QuoteBlock extends BodyBlock {
  const QuoteBlock(this.blocks);
  final List<BodyBlock> blocks;
}

final class CodeBlock extends BodyBlock {
  const CodeBlock(this.text, {this.language});
  final String text;
  final String? language;
}

/// Display maths — a ```latex fence, or `$$…$$` standing on its own.
final class MathBlock extends BodyBlock {
  const MathBlock(this.tex);
  final String tex;
}

final class RuleBlock extends BodyBlock {
  const RuleBlock();
}

final class TableBlock extends BodyBlock {
  const TableBlock({required this.header, required this.rows, required this.alignments});

  final List<List<BodyToken>> header;
  final List<List<List<BodyToken>>> rows;
  final List<TextAlignment> alignments;
}

enum TextAlignment { start, center, end }

// ---------------------------------------------------------------------------

final _fenceOpen = RegExp(r'^ {0,3}```([^\r\n]*)$');
final _fenceClose = RegExp(r'^ {0,3}```\s*$');
final _displayMathLine = RegExp(r'^\s*\$\$([\s\S]*?)\$\$\s*$');
final _heading = RegExp(r'^ {0,3}(#{1,6})\s+(.*)$');
final _rule = RegExp(r'^ {0,3}(?:-{3,}|\*{3,}|_{3,})\s*$');
final _quote = RegExp(r'^ {0,3}>\s?(.*)$');
final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _ordered = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(.*)$');
final _task = RegExp(r'^\[([ xX])\]\s+(.*)$');
final _tableRow = RegExp(r'^\s*\|(.+)\|\s*$');
final _tableRule = RegExp(r'^\s*\|(\s*:?-{1,}:?\s*\|)+\s*$');

/// Split a body into blocks.
///
/// [extended] turns on the markdown the site does not do. With it off the result is
/// fences, display maths and one paragraph per run of ordinary text, newlines intact.
List<BodyBlock> markdownBlocks(String body, {required bool extended}) {
  final normalized = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final blocks = <BodyBlock>[];
  final pending = <String>[];

  void flush() {
    if (pending.isEmpty) return;
    final text = pending.join('\n');
    pending.clear();
    if (text.trim().isEmpty) {
      // A run of blank lines between blocks is spacing, not content.
      return;
    }
    blocks.addAll(extended ? _extendedBlocks(text) : [ParagraphBlock(_spans(text))]);
  }

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];

    if (_fenceOpen.firstMatch(line) case final open?) {
      final language = open[1]!.trim().toLowerCase();
      final content = <String>[];
      var closed = false;
      var scan = index + 1;
      for (; scan < lines.length; scan++) {
        if (_fenceClose.hasMatch(lines[scan])) {
          closed = true;
          break;
        }
        content.add(lines[scan]);
      }
      // An unterminated fence is not a fence; the site's regex requires the closer.
      if (!closed) {
        pending.add(line);
        continue;
      }
      flush();
      final text = content.join('\n');
      blocks.add(
        language == 'latex' || language == 'tex'
            ? MathBlock(text)
            : CodeBlock(text, language: language.isEmpty ? null : language),
      );
      index = scan;
      continue;
    }

    if (_displayMathLine.firstMatch(line) case final math?) {
      flush();
      blocks.add(MathBlock(math[1]!.trim()));
      continue;
    }

    // A lone `$$` opens a multi-line display block. Without a closer it is just
    // text, so the scan has to find one before anything is consumed.
    if (line.trim() == r'$$') {
      final content = <String>[];
      var scan = index + 1;
      for (; scan < lines.length && lines[scan].trim() != r'$$'; scan++) {
        content.add(lines[scan]);
      }
      if (scan < lines.length) {
        flush();
        blocks.add(MathBlock(content.join('\n').trim()));
        index = scan;
        continue;
      }
    }

    pending.add(line);
  }
  flush();

  return blocks.isEmpty ? [ParagraphBlock(_spans(normalized))] : blocks;
}

/// Line-based block parsing, for the opt-in markdown.
List<BodyBlock> _extendedBlocks(String text) {
  final lines = text.split('\n');
  final blocks = <BodyBlock>[];
  final paragraph = <String>[];

  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final joined = paragraph.join('\n');
    paragraph.clear();
    if (joined.trim().isEmpty) return;
    blocks.add(ParagraphBlock(_spans(joined)));
  }

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];

    if (line.trim().isEmpty) {
      flushParagraph();
      continue;
    }
    if (_rule.hasMatch(line)) {
      flushParagraph();
      blocks.add(const RuleBlock());
      continue;
    }
    if (_heading.firstMatch(line) case final match?) {
      flushParagraph();
      blocks.add(HeadingBlock(match[1]!.length, _spans(match[2]!)));
      continue;
    }
    if (_quote.hasMatch(line)) {
      flushParagraph();
      final quoted = <String>[];
      var scan = index;
      for (; scan < lines.length; scan++) {
        final inner = _quote.firstMatch(lines[scan]);
        if (inner == null) break;
        quoted.add(inner[1]!);
      }
      blocks.add(QuoteBlock(_extendedBlocks(quoted.join('\n'))));
      index = scan - 1;
      continue;
    }
    // A table needs its `|---|` rule on the next line, or it is just text with pipes.
    if (_tableRow.hasMatch(line) &&
        index + 1 < lines.length &&
        _tableRule.hasMatch(lines[index + 1])) {
      flushParagraph();
      final header = _tableCells(line);
      final alignments = _alignments(lines[index + 1]);
      final rows = <List<List<BodyToken>>>[];
      var scan = index + 2;
      for (; scan < lines.length && _tableRow.hasMatch(lines[scan]); scan++) {
        rows.add(_tableCells(lines[scan]));
      }
      blocks.add(TableBlock(header: header, rows: rows, alignments: alignments));
      index = scan - 1;
      continue;
    }
    if (_ordered.firstMatch(line) case final match?) {
      flushParagraph();
      blocks.add(ListItemBlock(
        indent: _indentLevel(match[1]!),
        ordinal: int.parse(match[2]!),
        spans: _spans(match[3]!),
      ));
      continue;
    }
    if (_bullet.firstMatch(line) case final match?) {
      flushParagraph();
      final rest = match[2]!;
      final task = _task.firstMatch(rest);
      blocks.add(ListItemBlock(
        indent: _indentLevel(match[1]!),
        spans: _spans(task == null ? rest : task[2]!),
        checked: task == null ? null : task[1]!.toLowerCase() == 'x',
      ));
      continue;
    }
    paragraph.add(line);
  }
  flushParagraph();
  return blocks;
}

/// Two spaces or one tab to a level, capped so a stray indent cannot run off screen.
int _indentLevel(String whitespace) {
  final spaces = whitespace.replaceAll('\t', '  ').length;
  return (spaces ~/ 2).clamp(0, 4);
}

List<List<BodyToken>> _tableCells(String line) => [
  for (final cell in _tableRow.firstMatch(line)![1]!.split('|'))
    _spans(cell.trim()),
];

List<TextAlignment> _alignments(String rule) => [
  for (final cell in _tableRule.firstMatch(rule) == null
      ? const <String>[]
      : rule.trim().replaceAll(RegExp(r'^\||\|$'), '').split('|'))
    switch (cell.trim()) {
      final value when value.startsWith(':') && value.endsWith(':') => TextAlignment.center,
      final value when value.endsWith(':') => TextAlignment.end,
      _ => TextAlignment.start,
    },
];

/// The block layer adds no inline emphasis of its own.
///
/// `*bold*`, `_underline_` and `~strikethrough~` are all rendered unconditionally by
/// [tokenizeBody], because the site renders them unconditionally. There is nothing
/// left for this layer to claim, and a second pass over the same markers would only
/// disagree with the first.
List<BodyToken> _spans(String text) => tokenizeBody(text);
