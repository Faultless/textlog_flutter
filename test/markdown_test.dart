import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/body_tokens.dart';
import 'package:textlog/core/markdown.dart';
import 'package:textlog/core/polls.dart';

/// The spans of a body with no block structure — the common case.
List<BodyToken> spansOf(String body, {bool extended = true}) {
  final blocks = markdownBlocks(body, extended: extended);
  return blocks.whereType<ParagraphBlock>().expand((block) => block.spans).toList();
}

String textOf(Iterable<BodyToken> spans) => spans.map((span) {
  return switch (span) {
    PlainText(:final text) => text,
    StyledText(:final text) => text,
    LinkToken(:final text) => text,
    MentionToken(:final handle) => '@$handle',
    TagToken(:final tag) => '#$tag',
    MathToken(:final tex) => tex,
  };
}).join();

void main() {
  // ------------------------------------------------------------------ always on
  //
  // Everything in this group is rendered whether or not the markdown setting is
  // on, because textlog.cc renders it. Turning it off must not hide content.

  group('parity with the site, setting off', () {
    test('inline code is a code run, not literal backticks', () {
      final code = spansOf('run `flutter test` now', extended: false)
          .whereType<StyledText>()
          .single;
      expect(code.code, isTrue);
      expect(code.text, 'flutter test');
    });

    test('a fenced block becomes its own block', () {
      final blocks = markdownBlocks('look:\n```dart\nvoid main() {}\n```', extended: false);
      final code = blocks.whereType<CodeBlock>().single;
      expect(code.language, 'dart');
      expect(code.text, 'void main() {}');
    });

    test('an unterminated fence is not a fence', () {
      final blocks = markdownBlocks('```\nno closer', extended: false);
      expect(blocks.whereType<CodeBlock>(), isEmpty);
    });

    test('a latex fence is maths, not code', () {
      final blocks = markdownBlocks('```latex\n\\frac12\n```', extended: false);
      expect(blocks.whereType<MathBlock>().single.tex, r'\frac12');
      expect(blocks.whereType<CodeBlock>(), isEmpty);
    });

    test('single tildes strike through, as the site does', () {
      // The old app only understood ~~this~~, behind the markdown setting.
      expect(spansOf('~gone~', extended: false).whereType<StyledText>().single.strike, isTrue);
      expect(spansOf('~~gone~~', extended: false).whereType<StyledText>().single.strike, isTrue);
    });

    test('three tildes are not strikethrough', () {
      expect(spansOf('~~~x~~~', extended: false).whereType<StyledText>(), isEmpty);
    });

    test('a struck run keeps its links tappable', () {
      final spans = spansOf('~see @stagas~', extended: false);
      expect(spans.whereType<MentionToken>().single.handle, 'stagas');
    });

    test('markdown links work with the setting off', () {
      final link = spansOf('[repo](https://github.com/stagas/textlog)', extended: false)
          .whereType<LinkToken>()
          .single;
      expect(link.url, 'https://github.com/stagas/textlog');
      expect(link.text, 'repo');
    });

    test('a markdown link may leave the scheme out', () {
      // stagas' own bio does exactly this.
      final link = spansOf('[me](github.com/stagas)', extended: false)
          .whereType<LinkToken>()
          .single;
      expect(link.url, 'https://github.com/stagas');
    });

    test('a markdown destination that is not just a url is left alone', () {
      expect(markdownUrl('not a url at all'), isNull);
      expect(markdownUrl('example.com and more'), isNull);
    });

    test('inline maths is its own span', () {
      final maths = spansOf(r'so $x^2$ then', extended: false).whereType<MathToken>().single;
      expect(maths.tex, 'x^2');
    });

    test(r'a lone dollar amount is not maths', () {
      expect(spansOf(r'it cost $5 and $6', extended: false).whereType<MathToken>(), isEmpty);
    });

    test(r'$$ on its own lines is a display block', () {
      final blocks = markdownBlocks('before\n\$\$\n\\sum_{i}i\n\$\$\nafter', extended: false);
      expect(blocks.whereType<MathBlock>().single.tex, r'\sum_{i}i');
    });

    test('maths inside code stays code', () {
      final spans = spansOf(r'`$x$`', extended: false);
      expect(spans.whereType<MathToken>(), isEmpty);
      expect(spans.whereType<StyledText>().single.code, isTrue);
    });

    test('a body with none of this is one paragraph, newlines intact', () {
      final blocks = markdownBlocks('one\ntwo\n\nthree', extended: false);
      expect(blocks, hasLength(1));
      expect(textOf((blocks.single as ParagraphBlock).spans), 'one\ntwo\n\nthree');
    });
  });

  // ------------------------------------------------------- links and their labels

  group('link labels', () {
    setUp(() => linkOrigin = 'https://textlog.cc');

    test('a link home reads as a path', () {
      expect(shortLinkLabel('https://textlog.cc/post/12'), '/post/12');
      expect(shortLinkLabel('https://textlog.cc'), 'textlog.cc');
      expect(shortLinkLabel('https://textlog.cc/'), 'textlog.cc');
    });

    test('anything else loses its scheme and its www', () {
      expect(shortLinkLabel('https://www.example.com/a'), 'example.com/a');
      expect(shortLinkLabel('http://example.com'), 'example.com');
    });

    test('the host is kept whole and only the path may break', () {
      expect(linkBreakPoint('example.com/a/b'), 'example.com'.length);
      expect(linkBreakPoint('example.com'), 'example.com'.length);
    });

    test('a bare url is labelled the way the site labels it', () {
      final link = spansOf('go to https://textlog.cc/hot now', extended: false)
          .whereType<LinkToken>()
          .single;
      expect(link.url, 'https://textlog.cc/hot');
      expect(link.text, '/hot');
    });

    test('a schemeless domain still links', () {
      final link = spansOf('see github.com/stagas/textlog for the code', extended: false)
          .whereType<LinkToken>()
          .single;
      expect(link.url, 'https://github.com/stagas/textlog');
    });

    test('a sentence-ending word is not a domain', () {
      // `etc.` and `e.g.` have no real TLD after the dot.
      expect(spansOf('and so on, etc. done', extended: false).whereType<LinkToken>(), isEmpty);
      expect(spansOf('use it, e.g. here', extended: false).whereType<LinkToken>(), isEmpty);
    });

    test('sentence punctuation stays outside the link', () {
      final spans = spansOf('read https://textlog.cc/api.', extended: false);
      expect(spans.whereType<LinkToken>().single.url, 'https://textlog.cc/api');
      expect((spans.last as PlainText).text, '.');
    });

    test('a closing bracket the link did not open stays outside it', () {
      final spans = spansOf('(see https://textlog.cc/api)', extended: false);
      expect(spans.whereType<LinkToken>().single.url, 'https://textlog.cc/api');
    });

    test('an email local part is not a mention', () {
      expect(spansOf('mail hi@example.com', extended: false).whereType<MentionToken>(), isEmpty);
    });
  });

  // -------------------------------------------------------------------- hashtags

  group('hashtags follow the server rules', () {
    test('unicode letters count', () {
      expect(extractHashtags('un #café et #日本語'), ['café', '日本語']);
    });

    test('the sixth hashtag is ordinary text', () {
      expect(extractHashtags('#a #b #c #d #e #f'), ['a', 'b', 'c', 'd', 'e']);
    });

    test('a hash inside code is not a tag', () {
      expect(extractHashtags('`#nope` but #yes'), ['yes']);
      expect(extractHashtags('```\n#nope\n```\n#yes'), ['yes']);
    });

    test('a fragment in a url is not a tag', () {
      expect(extractHashtags('https://example.com/a#nope and #yes'), ['yes']);
    });

    test('ascii art is opt-in by tag, and the cap applies to it too', () {
      expect(containsAsciiArt('┌──┐ #ascii'), isTrue);
      expect(containsAsciiArt('#a #b #c #d #e #ascii'), isFalse);
    });
  });

  // --------------------------------------------------------------------- spoilers

  group('spoilers', () {
    test('a #spoiler line splits the body', () {
      final split = splitSpoilerBody('the setup #spoiler\nthe twist');
      expect(split.hasSpoiler, isTrue);
      expect(split.visible, 'the setup #spoiler');
      expect(split.hidden, 'the twist');
    });

    test('a body without one is all visible', () {
      final split = splitSpoilerBody('nothing hidden');
      expect(split.hasSpoiler, isFalse);
      expect(split.visible, 'nothing hidden');
    });
  });

  // ------------------------------------------------------------------------ polls

  group('polls', () {
    test('a #poll line and its options parse', () {
      final poll = parsePoll('tabs or spaces? #poll\ntabs\nspaces')!;
      expect(poll.question, 'tabs or spaces?');
      expect(poll.options, ['tabs', 'spaces']);
    });

    test('the options are not left in the body', () {
      expect(pollDisplayBody('tabs or spaces? #poll\ntabs\nspaces'),
          'tabs or spaces? #poll');
    });

    test('a body with no poll is untouched', () {
      expect(pollDisplayBody('just a post'), 'just a post');
      expect(parsePoll('just a post'), isNull);
    });

    test('fewer than two options, or a duplicate, is not a poll', () {
      expect(parsePoll('one? #poll\nonly'), isNull);
      expect(parsePoll('two? #poll\nsame\nsame'), isNull);
    });

    test('nine options is not a poll', () {
      expect(parsePoll('q #poll\n${List.generate(9, (i) => 'o$i').join('\n')}'), isNull);
    });

    test('a poll needs a question', () {
      expect(parsePoll('#poll\na\nb'), isNull);
    });
  });

  // -------------------------------------------------- opt-in block markdown
  //
  // The site keeps a post body flat, so all of this is behind the setting.

  group('markdown blocks, setting on', () {
    test('headings carry their level and drop the hashes', () {
      final heading = markdownBlocks('## Notes', extended: true)
          .whereType<HeadingBlock>()
          .single;
      expect(heading.level, 2);
      expect(textOf(heading.spans), 'Notes');
    });

    test('a hashtag is not a heading', () {
      final blocks = markdownBlocks('#open_source rules', extended: true);
      expect(blocks.whereType<HeadingBlock>(), isEmpty);
      expect(spansOf('#open_source rules').whereType<TagToken>().single.tag, 'open_source');
    });

    test('bullets accept -, * and +', () {
      for (final marker in ['-', '*', '+']) {
        final item = markdownBlocks('$marker one', extended: true)
            .whereType<ListItemBlock>()
            .single;
        expect(item.ordinal, isNull, reason: 'marker $marker');
        expect(textOf(item.spans), 'one');
      }
    });

    test('ordered lists keep their numbers', () {
      final items = markdownBlocks('1. one\n2. two', extended: true)
          .whereType<ListItemBlock>()
          .toList();
      expect(items.map((item) => item.ordinal), [1, 2]);
    });

    test('nesting is by indentation', () {
      final items = markdownBlocks('- a\n  - b\n    - c', extended: true)
          .whereType<ListItemBlock>()
          .toList();
      expect(items.map((item) => item.indent), [0, 1, 2]);
    });

    test('task lists carry their state', () {
      final items = markdownBlocks('- [ ] todo\n- [x] done', extended: true)
          .whereType<ListItemBlock>()
          .toList();
      expect(items.map((item) => item.checked), [false, true]);
      expect(textOf(items.first.spans), 'todo');
    });

    test('blockquotes nest their own blocks', () {
      final quote = markdownBlocks('> ## in here\n> and text', extended: true)
          .whereType<QuoteBlock>()
          .single;
      expect(quote.blocks.whereType<HeadingBlock>(), hasLength(1));
      expect(quote.blocks.whereType<ParagraphBlock>(), hasLength(1));
    });

    test('a table needs its rule line', () {
      final table = markdownBlocks('| a | b |\n|---|--:|\n| 1 | 2 |', extended: true)
          .whereType<TableBlock>()
          .single;
      expect(table.header.map(textOf), ['a', 'b']);
      expect(table.rows.single.map(textOf), ['1', '2']);
      expect(table.alignments, [TextAlignment.start, TextAlignment.end]);
    });

    test('pipes without a rule line are just text', () {
      expect(markdownBlocks('a | b', extended: true).whereType<TableBlock>(), isEmpty);
    });

    test('horizontal rules', () {
      for (final rule in ['---', '***', '___']) {
        expect(markdownBlocks(rule, extended: true).whereType<RuleBlock>(), hasLength(1),
            reason: rule);
      }
    });

    test('bold and italic', () {
      expect(spansOf('**b**').whereType<StyledText>().single.bold, isTrue);
      expect(spansOf('__b__').whereType<StyledText>().single.bold, isTrue);
      expect(spansOf('*i*').whereType<StyledText>().single.italic, isTrue);
      expect(spansOf('_i_').whereType<StyledText>().single.italic, isTrue);
    });

    test('emphasis markers are removed from the rendered text', () {
      expect(textOf(spansOf('a **b** c')), 'a b c');
    });

    test('unmatched markers stay literal', () {
      expect(spansOf('2 * 3 = 6').whereType<StyledText>(), isEmpty);
    });

    test('an underscore inside a word is not italics', () {
      // Handles routinely contain them.
      expect(spansOf('snake_case_name').whereType<StyledText>(), isEmpty);
    });

    test('mentions and hashtags survive inside emphasis', () {
      expect(spansOf('**@stagas**').whereType<MentionToken>().single.handle, 'stagas');
    });

    test('CRLF bodies do not leave a carriage return behind', () {
      final blocks = markdownBlocks('- one\r\n- two', extended: true)
          .whereType<ListItemBlock>()
          .toList();
      expect(blocks.map((item) => textOf(item.spans)), ['one', 'two']);
    });
  });

  test('the setting never changes what gets linked', () {
    const body = 'hi @ege see #tlog at https://textlog.cc';
    for (final extended in [false, true]) {
      final spans = spansOf(body, extended: extended);
      expect(spans.whereType<MentionToken>().single.handle, 'ege');
      expect(spans.whereType<TagToken>().single.tag, 'tlog');
      expect(spans.whereType<LinkToken>().single.url, 'https://textlog.cc');
    }
  });
}
