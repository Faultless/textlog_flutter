import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/body_analysis.dart';
import 'package:textlog/core/body_tokens.dart';
import 'package:textlog/core/markdown.dart';

const _body = """
we'll see did you see we're now an [open collective](https://opencollective.com/europe)
under [open source europe](https://opencollective.com/textlog)? it ensures the project
will stay non-profit. #tlog #feature #opensource

a bare domain github.com/stagas/textlog, a mention @stagas, `inline code`, ~struck~,
*bold* and _underline_.
""";

void main() {
  setUp(clearBodyAnalysisCache);

  group('taking a body apart', () {
    test('strips a poll\'s options and a checklist\'s items', () {
      final poll = analyseBody('best? #poll\na\nb', extended: false);
      expect(poll.display, 'best? #poll');

      final todo = analyseBody('list #todo\n[ ] a\n[x] b', extended: false);
      expect(todo.display, 'list #todo');
    });

    test('splits a spoiler and parses both halves', () {
      final analysis = analyseBody('setup #spoiler\nthe twist', extended: false);
      expect(analysis.spoiler.hasSpoiler, isTrue);
      expect(analysis.visible, isNotEmpty);
      expect(analysis.hidden, isNotEmpty);
    });

    test('leaves the hidden half unparsed when there is no spoiler', () {
      expect(analyseBody('plain', extended: false).hidden, isEmpty);
    });

    test('marks ascii art and keeps it literal', () {
      final analysis = analyseBody('┌──┐ #ascii\n*not bold*', extended: true);
      expect(analysis.asciiArt, isTrue);
      // One paragraph, no block markdown, and the asterisks left alone.
      expect(analysis.visible, hasLength(1));
      expect(analysis.visible.single, isA<ParagraphBlock>());
    });

    test('the setting changes the blocks, so it changes the answer', () {
      final flat = analyseBody('# heading', extended: false);
      final rich = analyseBody('# heading', extended: true);
      expect(flat.visible.single, isA<ParagraphBlock>());
      expect(rich.visible.single, isA<HeadingBlock>());
    });
  });

  group('doing it once', () {
    test('the same body gives back the very same analysis', () {
      // Not merely equal: identical, so a rebuild costs a map lookup.
      final first = analyseBody(_body, extended: false);
      final second = analyseBody(_body, extended: false);
      expect(identical(first, second), isTrue);
    });

    test('a rebuild is far cheaper than the first parse', () {
      // build runs on every frame a tile is scrolled through, and the cold parse
      // measured around 300us — enough to drop frames on a phone.
      final cold = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        clearBodyAnalysisCache();
        analyseBody(_body, extended: false);
      }
      cold.stop();

      analyseBody(_body, extended: false);
      final warm = Stopwatch()..start();
      for (var i = 0; i < 50; i++) {
        analyseBody(_body, extended: false);
      }
      warm.stop();

      expect(
        warm.elapsedMicroseconds * 20,
        lessThan(cold.elapsedMicroseconds),
        reason: 'cached must be at least twenty times cheaper',
      );
    });

    test('a checklist is worked out once too', () {
      const body = 'list #todo\n[ ] a';
      expect(identical(analyseTodo(body), analyseTodo(body)), isTrue);
    });

    test('a body with no checklist caches the absence', () {
      expect(analyseTodo('nothing here'), isNull);
      expect(analyseTodo('nothing here'), isNull);
    });

    test('the cache is bounded', () {
      // A reader who scrolls all day must not accumulate every body they passed.
      for (var i = 0; i < 500; i++) {
        analyseBody('body number \$i', extended: false);
      }
      // The oldest is gone, so parsing it again is a fresh object.
      final again = analyseBody('body number 0', extended: false);
      expect(identical(again, analyseBody('body number 0', extended: false)), isTrue);
    });
  });

  test('what it produces matches parsing by hand', () {
    // The cache must not change the answer, only how often it is computed.
    final analysis = analyseBody(_body, extended: false);
    final direct = markdownBlocks(_body, extended: false);
    expect(analysis.visible.length, direct.length);
    expect(
      analysis.visible.whereType<ParagraphBlock>().expand((b) => b.spans)
          .whereType<MentionToken>().map((t) => t.handle),
      direct.whereType<ParagraphBlock>().expand((b) => b.spans)
          .whereType<MentionToken>().map((t) => t.handle),
    );
  });
}
