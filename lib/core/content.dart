/// Port of the server's `src/content.ts`, so what the app treats as a hashtag, a
/// mention, ASCII art or a spoiler is exactly what textlog.cc treats as one.
///
/// Pure in, pure out. Nothing here knows about Flutter.
library;

import 'tlds.dart';

/// The server caps a post at five hashtags, and anything past the fifth is ordinary
/// text — including for the ASCII-art check, so a drawing tagged sixth is not art.
const maxHashtagsPerPost = 5;

/// `[\p{L}\p{M}\p{N}_]` — the site's hashtag alphabet. Unicode, not ASCII: `#café`
/// and `#日本語` are tags on textlog.
const _tagCharacter = r'\p{L}\p{M}\p{N}_';

final _hashtag = RegExp('(?<![$_tagCharacter])#([$_tagCharacter]+)', unicode: true);

final _mention = RegExp(r'(?<![A-Za-z0-9_])@([A-Za-z0-9_]{2,24})(?![A-Za-z0-9_])');

/// A URL, either with a scheme or "fuzzy" — a bare `example.com/path`, which the
/// server links too. The TLD has to be a real one or every `etc.` would become a link.
final _schemeUrl = RegExp(
  r'(?:https?|mailto):(?://)?[^\s<>"\x27]+',
  caseSensitive: false,
);
final _fuzzyUrl = RegExp(
  r'(?:[A-Za-z0-9](?:[A-Za-z0-9\-_]*[A-Za-z0-9])?\.)+([A-Za-z]{2,63})'
  r'(?::\d{1,5})?(?:[/?#][^\s<>"\x27]*)?',
);

/// One matched URL: where it sits in the body, what it reads as, and where it goes.
final class UrlMatch {
  const UrlMatch({
    required this.start,
    required this.end,
    required this.raw,
    required this.url,
  });

  final int start;
  final int end;

  /// As written in the body — may lack a scheme.
  final String raw;

  /// Always absolute, so it can be handed to a browser.
  final String url;
}

/// Trailing `.`, `,`, `)` and friends belong to the sentence, not the link.
final _trailingPunctuation = RegExp(r'[.,!?;:\x27"]+$');

/// Non-overlapping URLs, scheme-bearing ones taking precedence over fuzzy ones.
List<UrlMatch> matchUrls(String body) {
  final matches = <UrlMatch>[];
  final taken = <int>[];

  void add(int start, int end, String raw, String url) {
    for (var index = 0; index + 1 < taken.length; index += 2) {
      if (start < taken[index + 1] && end > taken[index]) return;
    }
    taken.addAll([start, end]);
    matches.add(UrlMatch(start: start, end: end, raw: raw, url: url));
  }

  for (final match in _schemeUrl.allMatches(body)) {
    var raw = match[0]!;
    // A URL at the end of a sentence must not swallow the full stop, and one inside
    // brackets must not swallow the closing one.
    raw = _withoutTrailingNoise(raw);
    if (raw.isEmpty) continue;
    add(match.start, match.start + raw.length, raw, raw);
  }

  for (final match in _fuzzyUrl.allMatches(body)) {
    // A fuzzy match must start at a word boundary, or `foo@bar.com` and the tail of
    // an already-matched URL would both become links.
    final before = match.start == 0 ? '' : body[match.start - 1];
    if (before.isNotEmpty && !_fuzzyBoundary.hasMatch(before)) continue;
    if (!tlds.contains(match[1]!.toLowerCase())) continue;
    final raw = _withoutTrailingNoise(match[0]!);
    if (raw.isEmpty) continue;
    add(match.start, match.start + raw.length, raw, 'https://$raw');
  }

  matches.sort((a, b) => a.start.compareTo(b.start));
  return matches;
}

final _fuzzyBoundary = RegExp(r'[^A-Za-z0-9@._\-/:]');

String _withoutTrailingNoise(String raw) {
  var value = raw.replaceFirst(_trailingPunctuation, '');
  // Balance brackets: `(see example.com/a_(b))` keeps its inner pair, loses the outer.
  while (value.isNotEmpty && _closers.containsKey(value[value.length - 1])) {
    final closer = value[value.length - 1];
    final opener = _closers[closer]!;
    if (_count(value, opener) >= _count(value, closer)) break;
    value = value.substring(0, value.length - 1).replaceFirst(_trailingPunctuation, '');
  }
  return value;
}

const _closers = {')': '(', ']': '[', '}': '{'};

int _count(String value, String character) =>
    value.split(character).length - 1;

/// Blank out fenced and inline code, preserving offsets, so a `#` inside a snippet is
/// not read as a hashtag. Line-for-line port of the server's `withoutMarkdownCode`.
String withoutMarkdownCode(String body) {
  final characters = body.split('');

  // Fenced blocks first, whole lines at a time.
  var offset = 0;
  String? fenceMarker;
  var fenceLength = 0;
  for (final line in _lines(body)) {
    final content = line.replaceFirst(RegExp(r'\n$'), '');
    final opening = RegExp(r'^ {0,3}(`{3,}|~{3,})').firstMatch(content);
    final closing = fenceMarker != null &&
        RegExp('^ {0,3}${RegExp.escape(fenceMarker)}{$fenceLength,}\\s*\$')
            .hasMatch(content);
    if (fenceMarker != null || opening != null) {
      for (var index = offset; index < offset + line.length; index++) {
        if (characters[index] != '\n') characters[index] = ' ';
      }
      if (closing) {
        fenceMarker = null;
      } else if (fenceMarker == null && opening != null) {
        fenceMarker = opening[1]![0];
        fenceLength = opening[1]!.length;
      }
    }
    offset += line.length;
  }

  // Then inline spans, in whatever is left outside the fences.
  final outside = characters.join();
  final openers = RegExp('`+');
  var cursor = 0;
  while (cursor < outside.length) {
    final opener = openers.firstMatch(outside.substring(cursor));
    if (opener == null) break;
    final start = cursor + opener.start;
    final length = opener[0]!.length;
    final remainder = outside.substring(start + length);
    final closer = RegExp('(^|[^`])(`{$length})(?!`)').firstMatch(remainder);
    if (closer == null) {
      cursor = start + length;
      continue;
    }
    final end = start + length + closer.start + closer[1]!.length + length;
    for (var index = start; index < end; index++) {
      if (characters[index] != '\n') characters[index] = ' ';
    }
    cursor = end;
  }
  return characters.join();
}

/// Lines *with* their newline, so offsets add up.
Iterable<String> _lines(String body) =>
    RegExp(r'.*(?:\n|$)', dotAll: false).allMatches(body)
        .map((match) => match[0]!)
        .where((line) => line.isNotEmpty);

String normalizeHashtag(String tag) => tag.toLowerCase();

/// Every hashtag the server would index for this post, in order, capped at five and
/// ignoring anything inside code or inside a URL.
List<String> extractHashtags(String body) {
  final tags = <String>{};
  final searchable = withoutMarkdownCode(body);
  final urls = matchUrls(searchable);
  var count = 0;
  for (final match in _hashtag.allMatches(searchable)) {
    if (urls.any((url) => match.start >= url.start && match.start < url.end)) continue;
    if (count++ == maxHashtagsPerPost) break;
    tags.add(normalizeHashtag(match[1]!));
  }
  return tags.toList();
}

List<String> extractMentions(String body) => {
  for (final match in _mention.allMatches(body)) match[1]!.toLowerCase(),
}.toList();

/// Drawing is opt-in by hashtag. Those posts render with compact line spacing and no
/// markup at all, because art drawn on a character grid falls apart otherwise — and
/// because it is full of `_`, `*` and `~`, which emphasis rules would eat.
bool containsAsciiArt(String body) =>
    extractHashtags(body).any((tag) => tag == 'ascii' || tag == 'ascii_art');

/// A `#spoiler` line splits a body: everything up to and including that line is
/// shown, everything after it waits behind a "reveal".
final class SpoilerBody {
  const SpoilerBody(this.visible, this.hidden);

  final String visible;
  final String hidden;

  bool get hasSpoiler => hidden.isNotEmpty;
}

SpoilerBody splitSpoilerBody(String body) {
  final lines = body.split('\n');
  final marker = lines.indexWhere((line) => extractHashtags(line).contains('spoiler'));
  if (marker < 0) return SpoilerBody(body, '');
  return SpoilerBody(
    lines.sublist(0, marker + 1).join('\n'),
    lines.sublist(marker + 1).join('\n'),
  );
}
