/// The block layer above [tokenizeBody].
///
/// Two levels, deliberately:
///
/// * **Always on** — fenced code blocks, display `$$…$$` maths, blockquotes, and —
///   since the site grew them — tables, horizontal rules and lists. textlog.cc
///   renders all of these in an ordinary post body, so leaving them out would show
///   the reader something the author did not write.
/// * **Behind the `markdown` setting** — headings, task-list checkboxes, and the
///   looser CommonMark spellings of the blocks above (indented quotes, nested and
///   single-item lists). The site does *not* render these, so they are opt-in: on
///   means the app shows structure textlog.cc keeps flat.
///
/// The always-on parsers are ports of the site's own `markdownTable`, `markdownList`
/// and `markdownHorizontalRule`, so the setting cannot change what a table *is* —
/// only whether the extra CommonMark around it is drawn.
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
  const CodeBlock(this.text, {this.language, this.collapsed = false});

  /// This fence is the source the server ran — a `#exec` program, or the `#mermaid`
  /// diagram it drew. The site folds those behind a "show code" control, because the
  /// point of the post is the output underneath, not the listing that produced it.
  final bool collapsed;
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
  const TableBlock({
    required this.header,
    required this.rows,
    required this.alignments,
    this.separators = const {},
  });

  /// Indices into [rows] that were written as all dashes — `| --- | --- |` part way
  /// down a table. The site draws those as a heavier rule rather than a row of
  /// dashes, which is how a `cloc` table gets its total separated off.
  final Set<int> separators;

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

/// The site's own rule, which allows no indent: `/^>\s?/`. The looser [_quote] above
/// is CommonMark's, and stays with the opt-in markdown that asked for CommonMark.
final _plainQuote = RegExp(r'^>\s?');
final _bullet = RegExp(r'^(\s*)[-*+]\s+(.*)$');
final _ordered = RegExp(r'^(\s*)(\d{1,9})[.)]\s+(.*)$');
final _task = RegExp(r'^\[([ xX])\]\s+(.*)$');
// The site's own rules, for the blocks it renders in every post body. Ported from
// `markdownHorizontalRule`, `markdownList` and `markdownTable` in its `utils.ts`,
// and deliberately stricter than the CommonMark ones above: this is what textlog.cc
// actually draws, so it is what the app draws with the setting off.
final _siteRule = RegExp(r'^ {0,3}(?:(?:\*[ \t]*){3,}|(?:-[ \t]*){3,}|(?:_[ \t]*){3,})$');
final _siteListItem = RegExp(r'^ {0,3}(?:(\d+)\.|[-+*])[ \t]+(.+)$');
final _siteDelimiter = RegExp(r'^:?-{3,}:?$');

/// Split one table line into cells, the way the site does.
///
/// Not a plain `split('|')`: a `\|` is an escaped pipe and a run of backticks opens a
/// code span in which pipes are literal. Leading and trailing empties come from the
/// outer pipes and are dropped. Null when the line is not a table row at all.
List<String>? _siteTableCells(String line) {
  if (!line.contains('|')) return null;
  final cells = <String>[];
  final cell = StringBuffer();
  var codeTicks = 0;

  for (var index = 0; index < line.length; index++) {
    final character = line[index];
    if (character == r'\' && index + 1 < line.length && line[index + 1] == '|') {
      cell.write('|');
      index++;
    } else if (character == '`') {
      var ticks = 1;
      while (index + ticks < line.length && line[index + ticks] == '`') {
        ticks++;
      }
      if (codeTicks == 0) {
        codeTicks = ticks;
      } else if (codeTicks == ticks) {
        codeTicks = 0;
      }
      cell.write('`' * ticks);
      index += ticks - 1;
    } else if (character == '|' && codeTicks == 0) {
      cells.add(cell.toString().trim());
      cell.clear();
    } else {
      cell.write(character);
    }
  }
  cells.add(cell.toString().trim());

  if (cells.isNotEmpty && cells.first.isEmpty) cells.removeAt(0);
  if (cells.isNotEmpty && cells.last.isEmpty) cells.removeLast();
  return cells.length > 1 ? cells : null;
}

/// A table starting at [index], or null. Header, delimiter rule, then rows.
({TableBlock block, int end})? _siteTable(List<String> lines, int index) {
  if (index + 1 >= lines.length) return null;
  final headers = _siteTableCells(lines[index]);
  final delimiters = _siteTableCells(lines[index + 1]);
  if (headers == null || delimiters == null) return null;
  if (headers.length != delimiters.length) return null;
  if (!delimiters.every(_siteDelimiter.hasMatch)) return null;

  final rows = <List<List<BodyToken>>>[];
  final separators = <int>{};
  var scan = index + 2;
  for (; scan < lines.length; scan++) {
    final cells = _siteTableCells(lines[scan]);
    if (cells == null) break;
    // An all-dashes row is a section rule, not data.
    if (cells.every((cell) => RegExp(r'^-{3,}$').hasMatch(cell))) {
      separators.add(rows.length);
    }
    rows.add([
      for (var column = 0; column < headers.length; column++)
        _spans(column < cells.length ? cells[column] : ''),
    ]);
  }

  return (
    block: TableBlock(
      header: [for (final header in headers) _spans(header)],
      alignments: [
        for (final cell in delimiters)
          if (cell.startsWith(':') && cell.endsWith(':'))
            TextAlignment.center
          else if (cell.endsWith(':'))
            TextAlignment.end
          else
            TextAlignment.start,
      ],
      rows: rows,
      separators: separators,
    ),
    end: scan - 1,
  );
}

/// A run of list items starting at [index], or null. The site wants **two** — one
/// dashed line on its own is a sentence, not a list.
({List<ListItemBlock> items, int end})? _siteList(List<String> lines, int index) {
  final first = _siteListItem.firstMatch(lines[index]);
  if (first == null) return null;
  final ordered = first[1] != null;

  final items = <ListItemBlock>[];
  var scan = index;
  for (; scan < lines.length; scan++) {
    final item = _siteListItem.firstMatch(lines[scan]);
    if (item == null || (item[1] != null) != ordered) break;
    items.add(ListItemBlock(
      indent: 0,
      ordinal: ordered ? int.parse(item[1]!) : null,
      spans: _spans(item[2]!),
    ));
  }
  return items.length < 2 ? null : (items: items, end: scan - 1);
}

/// The line a `#exec` or `#mermaid` marker sits on, outside any fence.
///
/// The site's rule: the marker ends its line, and the fence it claims is the first
/// one after it — any language for `#exec`, and `mermaid` specifically for
/// `#mermaid`. Ported from `executableFenceIndexes`.
final _executionMarker = RegExp(r'(?:^|\s)#(exec|mermaid)\s*$');

/// Indices of the fence-opening lines whose code the site folds away.
Set<int> _collapsedFenceLines(List<String> lines) {
  final markers = <({int line, String kind})>[];
  final fences = <({int line, String language})>[];

  var inFence = false;
  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];
    if (_fenceOpen.firstMatch(line) case final open? when !inFence) {
      fences.add((line: index, language: open[1]!.trim().toLowerCase()));
      inFence = true;
      continue;
    }
    if (inFence) {
      if (_fenceClose.hasMatch(line)) inFence = false;
      continue;
    }
    if (_executionMarker.firstMatch(line) case final marker?) {
      markers.add((line: index, kind: marker[1]!));
    }
  }

  return {
    for (final marker in markers)
      ...switch (fences.where((fence) =>
          fence.line > marker.line &&
          (marker.kind == 'exec'
              ? fence.language.isNotEmpty
              : fence.language == 'mermaid'))) {
        final matches when matches.isNotEmpty => [matches.first.line],
        _ => const <int>[],
      },
  };
}

/// Split a body into blocks.
///
/// [extended] turns on the markdown the site does not do. With it off the result is
/// fences, display maths and one paragraph per run of ordinary text, newlines intact.
List<BodyBlock> markdownBlocks(String body, {required bool extended}) {
  final normalized = body.replaceAll('\r\n', '\n').replaceAll('\r', '\n');
  final lines = normalized.split('\n');
  final collapsed = _collapsedFenceLines(lines);
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
    blocks.addAll(extended ? _extendedBlocks(text) : _plainBlocks(text));
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
            : CodeBlock(
                text,
                language: language.isEmpty ? null : language,
                collapsed: collapsed.contains(index),
              ),
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
/// The blocks a body has whether or not the extra markdown is switched on.
///
/// Quoting is not part of that setting: the site renders a `>` line as a quote
/// unconditionally, so this runs in both modes. Fences never reach here — the scanner
/// above has already lifted them out, which is what keeps a `>` inside a code sample
/// literal, exactly as the site keeps it.
List<BodyBlock> _plainBlocks(String text) {
  final lines = text.split('\n');
  // A drawing is full of `>`, `-` and `|`, and reading those as quotes, rules and
  // tables would take it apart. The site leaves art alone for the same reason.
  if (containsAsciiArt(text)) return [ParagraphBlock(_spans(text))];

  final blocks = <BodyBlock>[];
  final paragraph = <String>[];

  // Blank lines are *not* a paragraph break here: the site renders a body
  // `white-space: pre-wrap`, so the gaps an author typed are the gaps they meant.
  // Only a block starting flushes what came before it.
  void flushParagraph() {
    if (paragraph.isEmpty) return;
    final joined = paragraph.join('\n');
    paragraph.clear();
    if (joined.trim().isEmpty) return;
    blocks.add(ParagraphBlock(_spans(joined)));
  }

  for (var index = 0; index < lines.length; index++) {
    final line = lines[index];

    // Consecutive `>` lines are one quote, not one per line.
    if (_plainQuote.hasMatch(line)) {
      flushParagraph();
      final quoted = <String>[];
      var scan = index;
      for (; scan < lines.length && _plainQuote.hasMatch(lines[scan]); scan++) {
        quoted.add(lines[scan].replaceFirst(_plainQuote, ''));
      }
      // Recursed, so `> > x` nests the way it reads.
      blocks.add(QuoteBlock(_plainBlocks(quoted.join('\n'))));
      index = scan - 1;
      continue;
    }

    if (_siteRule.hasMatch(line)) {
      flushParagraph();
      blocks.add(const RuleBlock());
      continue;
    }

    if (_siteTable(lines, index) case final table?) {
      flushParagraph();
      blocks.add(table.block);
      index = table.end;
      continue;
    }

    if (_siteList(lines, index) case final list?) {
      flushParagraph();
      blocks.addAll(list.items);
      index = list.end;
      continue;
    }

    paragraph.add(line);
  }

  flushParagraph();
  return blocks;
}

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
    // The same parser the site uses, so the setting cannot change what a table is.
    if (_siteTable(lines, index) case final table?) {
      flushParagraph();
      blocks.add(table.block);
      index = table.end;
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

/// The block layer adds no inline emphasis of its own.
///
/// `*bold*`, `_underline_` and `~strikethrough~` are all rendered unconditionally by
/// [tokenizeBody], because the site renders them unconditionally. There is nothing
/// left for this layer to claim, and a second pass over the same markers would only
/// disagree with the first.
List<BodyToken> _spans(String text) => tokenizeBody(text);
