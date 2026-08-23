/// Everything a post body has to be taken apart into, worked out once.
///
/// Rendering a body means asking a lot of questions about it: does it hold a poll, a
/// checklist, a spoiler, ASCII art; where do the links and mentions fall; what are its
/// blocks. Each answer is a pass over the string, and `build` runs on every frame a
/// tile is scrolled through — which measured at around 300us per body per build on a
/// desktop, and enough on a mid-range phone to drop frames and, in debug, to hang the
/// app outright.
///
/// A body is an immutable string, so all of it is worth computing once and keeping.
library;

import 'body_tokens.dart';
import 'content.dart';
import 'markdown.dart';
import 'polls.dart';
import 'todos.dart';

final class BodyAnalysis {
  const BodyAnalysis({
    required this.display,
    required this.asciiArt,
    required this.spoiler,
    required this.visible,
    required this.hidden,
  });

  /// The body with a poll's options and a checklist's items taken out — they are
  /// rendered as a poll and a checklist below, not as text above.
  final String display;

  final bool asciiArt;
  final SpoilerBody spoiler;

  /// Blocks for what is shown, and for what waits behind a `reveal`.
  final List<BodyBlock> visible;
  final List<BodyBlock> hidden;
}

/// Take [body] apart, reusing the answer when it has been asked before.
BodyAnalysis analyseBody(String body, {required bool extended}) {
  // The flag belongs in the key: it changes the blocks.
  final key = '$extended|$body';
  final held = _cache[key];
  if (held != null) return held;

  final display = todoDisplayBody(pollDisplayBody(body));
  final art = containsAsciiArt(display);
  final spoiler = splitSpoilerBody(display);

  // Art is literal: only references stay tappable, which is what the site's
  // `linkifyAsciiReferences` does.
  List<BodyBlock> blocks(String text) => art
      ? [ParagraphBlock(tokenizeBody(text))]
      : markdownBlocks(text, extended: extended);

  final analysis = BodyAnalysis(
    display: display,
    asciiArt: art,
    spoiler: spoiler,
    visible: blocks(spoiler.visible),
    hidden: spoiler.hasSpoiler ? blocks(spoiler.hidden) : const [],
  );

  if (_cache.length >= _limit) _cache.remove(_cache.keys.first);
  _cache[key] = analysis;
  return analysis;
}

/// A checklist, reusing the answer the same way. Separate because the checklist
/// widget asks for it independently of the body above it.
Todo? analyseTodo(String body) {
  if (_todos.containsKey(body)) return _todos[body];
  final todo = parseTodo(body);
  if (_todos.length >= _limit) _todos.remove(_todos.keys.first);
  _todos[body] = todo;
  return todo;
}

/// Bounded: a reader who scrolls all day must not accumulate every body they passed.
/// Insertion-ordered, so the oldest entries are simply the first.
const _limit = 300;

// A plain map: Dart's keep insertion order, so the oldest key is the first.
final _cache = <String, BodyAnalysis>{};
final _todos = <String, Todo?>{};

/// For tests that need to measure a cold parse.
void clearBodyAnalysisCache() {
  _cache.clear();
  _todos.clear();
}
