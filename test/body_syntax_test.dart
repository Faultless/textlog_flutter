import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/body_tokens.dart';
import 'package:textlog/core/markdown.dart';

/// The styled runs of a body, as (text, marker) pairs.
List<(String, String)> styled(String body) => [
  for (final token in tokenizeBody(body))
    if (token is StyledText)
      (
        token.text,
        [
          if (token.bold) 'bold',
          if (token.italic) 'italic',
          if (token.underline) 'underline',
          if (token.strike) 'strike',
          if (token.redacted) 'redacted',
          if (token.code) 'code',
        ].join('+'),
      ),
];

void main() {
  group('italics', () {
    test('slashes make italics', () {
      expect(styled('a /word/ b'), [('word', 'italic')]);
    });

    test('a URL keeps its slashes', () {
      // The whole reason the marker needs a word boundary in front of it.
      expect(styled('see https://textlog.cc/post/1 now'), isEmpty);
    });

    test('a path mid-word is not emphasis', () {
      expect(styled('and/or'), isEmpty);
      expect(styled('a/b/c'), isEmpty);
    });

    test('it can hold other emphasis', () {
      expect(styled('/*both*/'), [('both', 'bold+italic')]);
    });

    test('an escaped slash is literal', () {
      expect(styled(r'\/not italic/'), isEmpty);
    });
  });

  group('redactions', () {
    test('bars hide the words between them', () {
      expect(styled('the answer is |42| ok'), [('42', 'redacted')]);
    });

    test('a table row is not a redaction', () {
      // Doubled pipes are excluded at both ends, so a table's cells survive.
      expect(styled('|| a ||'), isEmpty);
    });

    test('it survives alongside a redaction of its own', () {
      expect(styled('|one| and |two|'), [('one', 'redacted'), ('two', 'redacted')]);
    });
  });

  group('quoting', () {
    List<String> shapes(String body, {bool extended = false}) => [
      for (final block in markdownBlocks(body, extended: extended))
        switch (block) {
          QuoteBlock() => 'quote',
          ParagraphBlock() => 'para',
          CodeBlock() => 'code',
          _ => 'other',
        },
    ];

    test('a > line is a quote with the markdown setting off', () {
      // The site quotes unconditionally, so this is not part of the opt-in markdown.
      expect(shapes('> quoted\nplain'), ['quote', 'para']);
    });

    test('consecutive lines are one quote', () {
      expect(shapes('> one\n> two\n> three'), ['quote']);
    });

    test('a > inside a fence stays literal', () {
      expect(shapes('```\n> not a quote\n```'), ['code']);
    });

    test('ascii art is left alone', () {
      // A drawing's first column is often `>`; quoting it would take it apart.
      const art = '   >>>>>\n  >     >\n >   o   >\n  >     >\n   >>>>>';
      expect(shapes(art), ['para']);
    });

    test('it nests', () {
      final blocks = markdownBlocks('> > deep', extended: false);
      final outer = blocks.single as QuoteBlock;
      expect(outer.blocks.single, isA<QuoteBlock>());
    });
  });
}
