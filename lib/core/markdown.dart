/// Rudimentary markdown, layered on top of the plain tokenizer.
///
/// Deliberately small: inline emphasis, links, bullets and headings. No nesting, no
/// tables, no code fences. Posts are 280 characters — block layout is not what is
/// missing from them, and every rule here is a rule that can disagree with what
/// textlog.cc actually shows, which renders bodies as plain text.
library;

import 'body_tokens.dart';

enum BlockKind { paragraph, bullet, heading }

final class BodyLine {
  const BodyLine({required this.kind, required this.spans, this.level = 0});

  final BlockKind kind;
  final List<BodyToken> spans;

  /// Heading depth, 1–3. Zero for anything else.
  final int level;
}

final _heading = RegExp(r'^(#{1,3})\s+(.*)$');
final _bullet = RegExp(r'^\s*[-*+]\s+(.*)$');
final _mdLink = RegExp(r'\[([^\]]+)\]\(([^)\s]+)\)');
final _emphasis = RegExp(r'\*\*(.+?)\*\*|~~(.+?)~~|\*(.+?)\*|_(.+?)_');

/// Split a body into lines, each with its block kind and inline spans.
List<BodyLine> markdownLines(String body) {
  return [
    for (final line in body.split('\n'))
      if (_heading.firstMatch(line) case final match?)
        BodyLine(
          kind: BlockKind.heading,
          level: match[1]!.length,
          spans: _inline(match[2]!),
        )
      else if (_bullet.firstMatch(line) case final match?)
        BodyLine(kind: BlockKind.bullet, spans: _inline(match[1]!))
      else
        BodyLine(kind: BlockKind.paragraph, spans: _inline(line)),
  ];
}

/// Markdown links are pulled out first: otherwise the plain tokenizer would see the
/// bare URL inside `[label](url)` and link that instead, losing the label.
List<BodyToken> _inline(String text) {
  final spans = <BodyToken>[];
  var end = 0;

  for (final match in _mdLink.allMatches(text)) {
    spans.addAll(_plain(text.substring(end, match.start)));
    spans.add(LinkToken(match[2]!, label: match[1]!));
    end = match.end;
  }
  spans.addAll(_plain(text.substring(end)));
  return spans;
}

/// Run the shared tokenizer, then look for emphasis inside whatever stayed plain —
/// so `**@someone**` still links the mention.
List<BodyToken> _plain(String text) {
  if (text.isEmpty) return const [];
  return [
    for (final token in tokenizeBody(text))
      if (token is PlainText) ..._emphasised(token.text) else token,
  ];
}

List<BodyToken> _emphasised(String text) {
  final spans = <BodyToken>[];
  var end = 0;

  void plain(String value) {
    if (value.isNotEmpty) spans.add(PlainText(value));
  }

  for (final match in _emphasis.allMatches(text)) {
    plain(text.substring(end, match.start));
    spans.add(
      switch (match) {
        _ when match[1] != null => StyledText(match[1]!, bold: true),
        _ when match[2] != null => StyledText(match[2]!, strike: true),
        _ when match[3] != null => StyledText(match[3]!, italic: true),
        _ => StyledText(match[4]!, italic: true),
      },
    );
    end = match.end;
  }

  plain(text.substring(end));
  return spans;
}
