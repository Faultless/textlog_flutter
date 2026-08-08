import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/body_tokens.dart';
import 'package:textlog/core/markdown.dart';

List<BodyToken> spansOf(String body) => markdownLines(body).single.spans;

void main() {
  group('blocks', () {
    test('headings carry their level and drop the hashes', () {
      final line = markdownLines('## Notes').single;
      expect(line.kind, BlockKind.heading);
      expect(line.level, 2);
      expect((line.spans.single as PlainText).text, 'Notes');
    });

    test('a hashtag is not a heading', () {
      final line = markdownLines('#open_source rules').single;
      expect(line.kind, BlockKind.paragraph);
      expect(line.spans.whereType<TagToken>().single.tag, 'open_source');
    });

    test('bullets accept -, * and +', () {
      for (final marker in ['-', '*', '+']) {
        final line = markdownLines('$marker one').single;
        expect(line.kind, BlockKind.bullet, reason: 'marker $marker');
        expect((line.spans.single as PlainText).text, 'one');
      }
    });

    test('each newline is its own line', () {
      final lines = markdownLines('# Title\n- a\nplain');
      expect(lines.map((l) => l.kind), [
        BlockKind.heading,
        BlockKind.bullet,
        BlockKind.paragraph,
      ]);
    });
  });

  group('inline', () {
    test('bold, italic and strikethrough', () {
      expect((spansOf('**b**').single as StyledText).bold, isTrue);
      expect((spansOf('*i*').single as StyledText).italic, isTrue);
      expect((spansOf('_i_').single as StyledText).italic, isTrue);
      expect((spansOf('~~s~~').single as StyledText).strike, isTrue);
    });

    test('markdown links keep their label', () {
      final link = spansOf('see [the repo](https://github.com/stagas/textlog) ok')
          .whereType<LinkToken>()
          .single;
      expect(link.url, 'https://github.com/stagas/textlog');
      expect(link.label, 'the repo');
      expect(link.text, 'the repo');
    });

    test('a bare url still links, using itself as the label', () {
      final link = spansOf('go to https://textlog.cc now').whereType<LinkToken>().single;
      expect(link.label, isNull);
      expect(link.text, 'https://textlog.cc');
    });

    test('mentions and hashtags survive inside emphasis', () {
      final spans = spansOf('**@stagas**');
      expect(spans.whereType<MentionToken>().single.handle, 'stagas');
    });

    test('emphasis markers are removed from the rendered text', () {
      final text = spansOf('a **b** c').map((s) {
        return switch (s) {
          PlainText(:final text) => text,
          StyledText(:final text) => text,
          _ => '',
        };
      }).join();
      expect(text, 'a b c');
    });

    test('unmatched markers stay literal', () {
      final spans = spansOf('2 * 3 = 6');
      expect(spans.whereType<StyledText>(), isEmpty);
    });
  });

  test('markdown parsing never loses the plain tokenizer behaviour', () {
    // The same body, both ways, must link the same things.
    const body = 'hi @ege see #tlog at https://textlog.cc';
    final plain = tokenizeBody(body);
    final marked = spansOf(body);

    expect(
      marked.whereType<MentionToken>().map((t) => t.handle),
      plain.whereType<MentionToken>().map((t) => t.handle),
    );
    expect(
      marked.whereType<TagToken>().map((t) => t.tag),
      plain.whereType<TagToken>().map((t) => t.tag),
    );
    expect(
      marked.whereType<LinkToken>().map((t) => t.url),
      plain.whereType<LinkToken>().map((t) => t.url),
    );
  });
}
