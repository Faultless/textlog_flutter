import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/highlight.dart';

List<CodeToken> kindsOf(String code, String language) =>
    [for (final span in highlightCode(code, language: language)) span.kind];

String textOf(List<CodeSpan> spans) => spans.map((span) => span.text).join();

void main() {
  group('colouring a fence', () {
    test('nothing is lost, whatever the code', () {
      // The one property that matters: a highlighter that drops a character has
      // rewritten somebody's post.
      const code = "const x = 'a\\'b' // note\n/* block */ 0x1f\n";
      expect(textOf(highlightCode(code, language: 'js')), code);
      expect(textOf(highlightCode(code, language: 'python')), code);
      expect(textOf(highlightCode(code, language: 'rust')), code);
    });

    test('a language nobody highlights is one plain run', () {
      // The site colours js and python. Everything else is code, plainly.
      expect(kindsOf('fn main() {}', 'rust'), [CodeToken.plain]);
      expect(kindsOf('fn main() {}', ''), [CodeToken.plain]);
    });

    test('keywords, strings, numbers and comments in javascript', () {
      final spans = highlightCode("const n = 42 // why\n", language: 'js');
      expect(spans.first, const CodeSpan('const', CodeToken.keyword));
      expect(spans.any((s) => s.kind == CodeToken.number && s.text == '42'), isTrue);
      expect(spans.any((s) => s.kind == CodeToken.comment && s.text == '// why'), isTrue);
    });

    test('a block comment, and code after it', () {
      final spans = highlightCode('/* off */ let a', language: 'js');
      expect(spans.first, const CodeSpan('/* off */', CodeToken.comment));
      expect(spans.any((s) => s.kind == CodeToken.keyword && s.text == 'let'), isTrue);
    });

    test('a hash is a comment in python and not in javascript', () {
      expect(kindsOf('# hi', 'python'), [CodeToken.comment]);
      expect(kindsOf('# hi', 'js'), [CodeToken.plain]);
    });

    test('a docstring runs across lines; a plain quote does not', () {
      final doc = highlightCode('"""one\ntwo"""\n', language: 'python');
      expect(doc.first.kind, CodeToken.string);
      expect(doc.first.text, '"""one\ntwo"""');

      // An unclosed quote stops at the newline rather than painting the rest of
      // the post as a string.
      final broken = highlightCode("x = 'oops\ny = 1\n", language: 'python');
      expect(broken.any((s) => s.kind == CodeToken.string && s.text == "'oops"), isTrue);
      expect(broken.any((s) => s.kind == CodeToken.number && s.text == '1'), isTrue);
    });

    test('an escaped quote does not end the string', () {
      final spans = highlightCode(r"'a\'b'", language: 'js');
      expect(spans.single, const CodeSpan(r"'a\'b'", CodeToken.string));
    });

    test('a word that merely contains a keyword is not one', () {
      final spans = highlightCode('iffy classes', language: 'js');
      expect(spans.every((span) => span.kind == CodeToken.plain), isTrue);
    });

    test('nothing at all', () {
      expect(highlightCode('', language: 'js'), isEmpty);
    });
  });
}
