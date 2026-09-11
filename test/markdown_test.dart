import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/body_tokens.dart';
import 'package:textlog/core/content.dart';
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

    test('asterisks are bold and underscores are underline', () {
      // Not italics, and not behind the setting: the site renders both markers
      // unconditionally, so treating them as opt-in italics showed the reader
      // something the author did not write.
      for (final body in ['*b*', '**b**']) {
        final span = spansOf(body, extended: false).whereType<StyledText>().single;
        expect(span.bold, isTrue, reason: body);
        expect(span.underline, isFalse, reason: body);
      }
      for (final body in ['_u_', '__u__']) {
        final span = spansOf(body, extended: false).whereType<StyledText>().single;
        expect(span.underline, isTrue, reason: body);
        expect(span.bold, isFalse, reason: body);
      }
    });

    test('emphasis markers are removed from the rendered text', () {
      expect(textOf(spansOf('a **b** c', extended: false)), 'a b c');
    });

    test('emphasis combines rather than one winning', () {
      final span = spansOf('~*both*~', extended: false).whereType<StyledText>().single;
      expect(span.strike, isTrue);
      expect(span.bold, isTrue);
    });

    test('an unmatched marker stays literal', () {
      expect(spansOf('2 * 3 = 6', extended: false).whereType<StyledText>(), isEmpty);
    });

    test('mentions and hashtags survive inside emphasis', () {
      expect(
        spansOf('**@stagas**', extended: false).whereType<MentionToken>().single.handle,
        'stagas',
      );
    });

    test('a handle is not chopped up by its own underscores', () {
      // The underline rule would happily claim `_case_` out of the middle of a
      // handle, so a mention has to be matched before it — which it is, by index.
      final spans = spansOf('hi @snake_case_name', extended: false);
      expect(spans.whereType<MentionToken>().single.handle, 'snake_case_name');
      expect(spans.whereType<StyledText>(), isEmpty);
    });

    test('bare text with underscores is underlined, as the site does it', () {
      // Faithful rather than convenient: textlog underlines `case` here too.
      final spans = spansOf('snake_case_name', extended: false);
      expect(spans.whereType<StyledText>().single.underline, isTrue);
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

    test('the sixteenth hashtag is ordinary text', () {
      final sixteen = [for (var index = 0; index < 16; index++) '#t$index'].join(' ');
      expect(extractHashtags(sixteen), hasLength(maxHashtagsPerPost));
      expect(extractHashtags(sixteen), isNot(contains('t15')));
    });

    test('a hash inside code is not a tag', () {
      expect(extractHashtags('`#nope` but #ok'), ['ok']);
      expect(extractHashtags('```\n#nope\n```\n#ok'), ['ok']);
    });

    test('a fragment in a url is not a tag', () {
      expect(extractHashtags('https://example.com/a#nope and #ok'), ['ok']);
    });

    test('an escaped hash is not a tag', () {
      expect(extractHashtags(r'\#nope but #ok'), ['ok']);
      // An even run of backslashes escapes itself, so the tag survives.
      expect(extractHashtags(r'\\#ok'), ['ok']);
    });

    test('a tag is indexed singular, with underscores folded away', () {
      // The server's own rule — verified against textlog.cc, where `#cats` resolves
      // to the `cat` page.
      expect(extractHashtags('#cats'), ['cat']);
      expect(extractHashtags('#Cat'), ['cat']);
      expect(extractHashtags('#ascii_art'), ['asciiart']);
      // Words it keeps whole: a double s, a -us, a -sis, and the named exceptions.
      expect(extractHashtags('#news #bus #analysis #chess'), [
        'news',
        'bus',
        'analysis',
        'chess',
      ]);
      // `-ses` loses two letters, not one.
      expect(extractHashtags('#glasses'), ['glass']);
    });

    test('a PascalCase tag keeps the spelling it was written in', () {
      final tags = extractAuthoredHashtags('#ClaudeCode and #plain');
      expect(tags.map((tag) => tag.tag), ['claudecode', 'plain']);
      expect(pascalCaseHashtagDisplayName(tags.first.authored), 'ClaudeCode');
      expect(pascalCaseHashtagDisplayName(tags.last.authored), isNull);
    });

    test('ascii art is opt-in by tag, and the cap applies to it too', () {
      expect(containsAsciiArt('┌──┐ #ascii'), isTrue);
      // The underscored spelling folds onto the same tag.
      expect(containsAsciiArt('┌──┐ #ascii_art'), isTrue);
      final past = [for (var index = 0; index < 15; index++) '#t$index'].join(' ');
      expect(containsAsciiArt('$past #ascii'), isFalse);
    });
  });

  // ------------------------------------------------------ exec and mermaid sources

  group('the fence behind #exec and #mermaid is folded away', () {
    // The post is about what the server printed or drew; the listing is the working.
    CodeBlock fence(String body) =>
        markdownBlocks(body, extended: false).whereType<CodeBlock>().single;

    test('a #exec marker claims the next fence with a language', () {
      expect(fence('run it #exec\n```js\nconsole.log(1)\n```').collapsed, isTrue);
    });

    test('a #mermaid marker claims a mermaid fence', () {
      expect(fence('#mermaid\n```mermaid\ngraph TD;\n```').collapsed, isTrue);
    });

    test('a #mermaid marker does not claim some other language', () {
      expect(fence('#mermaid\n```js\nnot a diagram\n```').collapsed, isFalse);
    });

    test('an ordinary fence is left alone', () {
      expect(fence('look at this\n```js\nconsole.log(1)\n```').collapsed, isFalse);
    });

    test('a marker inside a fence is a string, not a marker', () {
      final blocks = markdownBlocks(
        '```text\n#exec\n```\n```js\nconsole.log(1)\n```',
        extended: false,
      ).whereType<CodeBlock>().toList();
      expect(blocks.every((block) => !block.collapsed), isTrue);
    });

    test('only the first matching fence is claimed', () {
      final blocks = markdownBlocks(
        '#exec\n```js\none\n```\nand\n```js\ntwo\n```',
        extended: false,
      ).whereType<CodeBlock>().toList();
      expect(blocks.map((block) => block.collapsed), [true, false]);
    });
  });

  // ------------------------------------------------- blocks the site always draws

  group('blocks the site draws with the setting off', () {
    // textlog.cc renders tables, rules and lists in an ordinary post body now, so
    // leaving them behind the `markdown` setting showed the reader something the
    // author did not write.
    List<BodyBlock> plain(String body) => markdownBlocks(body, extended: false);

    test('a table', () {
      final table = plain('| a | b |\n| --- | ---: |\n| 1 | 2 |')
          .whereType<TableBlock>()
          .single;
      expect(table.header.map(textOf), ['a', 'b']);
      expect(table.rows.single.map(textOf), ['1', '2']);
      expect(table.alignments, [TextAlignment.start, TextAlignment.end]);
    });

    test('a table row of all dashes is a section rule', () {
      final table = plain(
        '| lang | code |\n| --- | ---: |\n| dart | 10 |\n| --- | --- |\n| sum | 10 |',
      ).whereType<TableBlock>().single;
      expect(table.rows, hasLength(3));
      expect(table.separators, {1});
    });

    test('a pipe inside a code span does not split a cell', () {
      final table = plain('| a | b |\n| --- | --- |\n| `x | y` | 2 |')
          .whereType<TableBlock>()
          .single;
      expect(table.rows.single.length, 2);
      expect(textOf(table.rows.single.last), '2');
    });

    test('a horizontal rule', () {
      expect(plain('before\n---\nafter').whereType<RuleBlock>(), hasLength(1));
      expect(plain('before\n* * *\nafter').whereType<RuleBlock>(), hasLength(1));
    });

    test('a list, but only once it has two items', () {
      final items = plain('- one\n- two').whereType<ListItemBlock>().toList();
      expect(items.map((item) => textOf(item.spans)), ['one', 'two']);
      expect(
        plain('- lonely').whereType<ListItemBlock>(),
        isEmpty,
        reason: 'one dashed line is a sentence, as the site has it',
      );
    });

    test('an ordered list keeps the number it started on', () {
      final items = plain('3. three\n4. four').whereType<ListItemBlock>().toList();
      expect(items.map((item) => item.ordinal), [3, 4]);
    });

    test('and none of it touches ascii art', () {
      final art = plain('#ascii\n| a | b |\n| --- | --- |\n---\n- one\n- two');
      expect(art.single, isA<ParagraphBlock>());
    });

    test('blank lines inside a paragraph survive, because the site is pre-wrap', () {
      final paragraph = plain('one\n\nthree').whereType<ParagraphBlock>().single;
      expect(textOf(paragraph.spans), 'one\n\nthree');
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

    test('the content-warning spellings hide just the same', () {
      for (final tag in spoilerHashtags) {
        final split = splitSpoilerBody('warning #$tag\nthe rest');
        expect(split.hasSpoiler, isTrue, reason: '#$tag splits a body');
        expect(split.hidden, 'the rest');
      }
    });

    test('a spoiler tag inside a fence is a string, not a marker', () {
      final split = splitSpoilerBody('```\n#spoiler\n```\nstill visible');
      expect(split.hasSpoiler, isFalse);
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

    test('a table needs its rule line, of at least three dashes', () {
      // The site's rule is `^:?-{3,}:?$` — two dashes is not a delimiter.
      expect(
        markdownBlocks('| a | b |\n| - | - |\n| 1 | 2 |', extended: true)
            .whereType<TableBlock>(),
        isEmpty,
      );
      final table = markdownBlocks('| a | b |\n|---|---:|\n| 1 | 2 |', extended: true)
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
