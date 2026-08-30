/// Colouring a code fence, for the two languages the site colours.
///
/// textlog highlights `js` and `python` fences server-side with highlight.js and
/// sends the HTML to a browser. The API sends bodies as they were written, so the app
/// has to do its own — which is this: a small scanner over comments, strings, numbers
/// and keywords, in the same four colours the site's stylesheet gives those classes.
///
/// Deliberately not a parser. It is a hundred lines against a megabyte of
/// highlight.js, it never fails on code it does not understand — the worst it can do
/// is leave a run uncoloured — and a phone reading a two-line snippet does not need
/// more. Anything but those two languages comes back as one plain run.
library;

enum CodeToken { plain, keyword, string, comment, number }

final class CodeSpan {
  const CodeSpan(this.text, this.kind);

  final String text;
  final CodeToken kind;

  @override
  bool operator ==(Object other) =>
      other is CodeSpan && other.text == text && other.kind == kind;

  @override
  int get hashCode => Object.hash(text, kind);

  @override
  String toString() => '${kind.name}(${text.replaceAll('\n', r'\n')})';
}

/// The fence languages worth colouring, and their aliases — the site's own table.
const _languages = {
  'js': _js,
  'javascript': _js,
  'jsx': _js,
  'ts': _js,
  'typescript': _js,
  'py': _python,
  'python': _python,
};

const _js = _Rules(
  lineComment: '//',
  blockComment: ('/*', '*/'),
  quotes: {"'", '"', '`'},
  keywords: {
    'as', 'async', 'await', 'break', 'case', 'catch', 'class', 'const', 'continue',
    'default', 'delete', 'do', 'else', 'export', 'extends', 'false', 'finally',
    'for', 'from', 'function', 'get', 'if', 'import', 'in', 'instanceof', 'let',
    'new', 'null', 'of', 'return', 'set', 'static', 'super', 'switch', 'this',
    'throw', 'true', 'try', 'typeof', 'undefined', 'var', 'void', 'while', 'yield',
  },
);

const _python = _Rules(
  lineComment: '#',
  blockComment: null,
  quotes: {"'", '"'},
  keywords: {
    'and', 'as', 'assert', 'async', 'await', 'break', 'class', 'continue', 'def',
    'del', 'elif', 'else', 'except', 'False', 'finally', 'for', 'from', 'global',
    'if', 'import', 'in', 'is', 'lambda', 'None', 'nonlocal', 'not', 'or', 'pass',
    'raise', 'return', 'True', 'try', 'while', 'with', 'yield',
  },
);

final class _Rules {
  const _Rules({
    required this.lineComment,
    required this.blockComment,
    required this.quotes,
    required this.keywords,
  });

  final String lineComment;
  final (String, String)? blockComment;
  final Set<String> quotes;
  final Set<String> keywords;
}

/// [code] split into coloured runs, in order and losing nothing: joining every
/// span's text gives the input back exactly.
List<CodeSpan> highlightCode(String code, {String? language}) {
  final rules = _languages[language?.trim().toLowerCase()];
  if (rules == null || code.isEmpty) {
    return code.isEmpty ? const [] : [CodeSpan(code, CodeToken.plain)];
  }

  final spans = <CodeSpan>[];
  final plain = StringBuffer();
  var index = 0;

  void flush() {
    if (plain.isEmpty) return;
    spans.add(CodeSpan(plain.toString(), CodeToken.plain));
    plain.clear();
  }

  void take(int end, CodeToken kind) {
    flush();
    spans.add(CodeSpan(code.substring(index, end), kind));
    index = end;
  }

  while (index < code.length) {
    final rest = code.substring(index);

    if (rest.startsWith(rules.lineComment)) {
      final newline = code.indexOf('\n', index);
      take(newline < 0 ? code.length : newline, CodeToken.comment);
      continue;
    }

    if (rules.blockComment case (final open, final close) when rest.startsWith(open)) {
      final end = code.indexOf(close, index + open.length);
      take(end < 0 ? code.length : end + close.length, CodeToken.comment);
      continue;
    }

    final quote = rest.isEmpty ? '' : rest[0];
    if (rules.quotes.contains(quote)) {
      take(_stringEnd(code, index, quote), CodeToken.string);
      continue;
    }

    if (_isDigit(quote)) {
      var end = index;
      while (end < code.length && (_isWordChar(code[end]) || code[end] == '.')) {
        end++;
      }
      take(end, CodeToken.number);
      continue;
    }

    if (_isWordStart(quote)) {
      var end = index;
      while (end < code.length && _isWordChar(code[end])) {
        end++;
      }
      final word = code.substring(index, end);
      if (rules.keywords.contains(word)) {
        take(end, CodeToken.keyword);
      } else {
        plain.write(word);
        index = end;
      }
      continue;
    }

    plain.write(quote);
    index++;
  }

  flush();
  return spans;
}

/// Where the string starting at [start] ends: past its closing quote, or at the end
/// of the line for one that was never closed — an unterminated quote is a typo, and
/// colouring the rest of the file for it is how a highlighter makes a mess.
int _stringEnd(String code, int start, String quote) {
  // ''' and """ run across lines, which is most of what a Python docstring is.
  final triple = code.startsWith(quote * 3, start);
  final mark = triple ? quote * 3 : quote;
  var index = start + mark.length;

  while (index < code.length) {
    final character = code[index];
    if (character == r'\') {
      index += 2;
      continue;
    }
    if (!triple && character == '\n') return index;
    if (code.startsWith(mark, index)) return index + mark.length;
    index++;
  }
  return code.length;
}

bool _isDigit(String character) =>
    character.codeUnitAt(0) >= 0x30 && character.codeUnitAt(0) <= 0x39;

bool _isWordStart(String character) {
  final code = character.codeUnitAt(0);
  return (code >= 0x41 && code <= 0x5a) ||
      (code >= 0x61 && code <= 0x7a) ||
      character == '_' ||
      character == r'$';
}

bool _isWordChar(String character) =>
    _isWordStart(character) || _isDigit(character);
