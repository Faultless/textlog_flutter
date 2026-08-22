/// Port of the server's `linkTokens` / `linkify` (src/utils.ts), so bodies render
/// here the way they render on textlog.cc.
///
/// Pure in, pure out — the widget layer only decides how each token looks. Everything
/// in this file is rendered *unconditionally*, because the site renders it
/// unconditionally: inline code, fenced code, TeX, markdown links, strikethrough,
/// URLs, mentions and hashtags. The extra block-level markdown that textlog does not
/// do lives behind a setting, in `markdown.dart`.
library;

import 'content.dart';

export 'content.dart' show containsAsciiArt, extractHashtags, extractMentions, splitSpoilerBody;

sealed class BodyToken {
  const BodyToken();
}

final class PlainText extends BodyToken {
  const PlainText(this.text);
  final String text;
}

final class LinkToken extends BodyToken {
  const LinkToken(this.url, {this.label, this.raw});

  final String url;

  /// Set for a markdown `[label](url)`, and for a bare URL the site shortens.
  final String? label;

  /// As written in the body, when that differs from both label and url.
  final String? raw;

  String get text => label ?? url;
}

/// Emphasised run of plain text.
final class StyledText extends BodyToken {
  const StyledText(
    this.text, {
    this.bold = false,
    this.italic = false,
    this.strike = false,
    this.code = false,
  });

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;

  /// Inline `` `code` `` — rendered in a boxed, quieter run.
  final bool code;
}

/// Inline `$x$` TeX. Display `$$x$$` and ```latex fences become [MathBlock] instead.
final class MathToken extends BodyToken {
  const MathToken(this.tex);
  final String tex;
}

final class MentionToken extends BodyToken {
  const MentionToken(this.handle);
  final String handle;
}

final class TagToken extends BodyToken {
  const TagToken(this.tag);
  final String tag;
}

// ---------------------------------------------------------------------------
// Tokenizing
// ---------------------------------------------------------------------------

enum _Kind { codeFence, latexFence, code, math, markdownLink, strike, url, reference }

final class _Token {
  const _Token(this.kind, this.start, this.end, this.raw, {this.label, this.url, this.display = false});

  final _Kind kind;
  final int start;
  final int end;
  final String raw;
  final String? label;
  final String? url;
  final bool display;
}

/// The site's precedence: a fence wins over inline code, which wins over maths,
/// which wins over a markdown link, and so on down to a bare reference.
const _priority = {
  _Kind.codeFence: 0,
  _Kind.latexFence: 0,
  _Kind.code: 1,
  _Kind.math: 2,
  _Kind.markdownLink: 3,
  _Kind.strike: 4,
  _Kind.url: 5,
  _Kind.reference: 6,
};

final _fence = RegExp(r'^```([^\r\n]*)\r?\n([\s\S]*?)\r?\n```(?=\r?$)', multiLine: true);
final _inlineCode = RegExp(r'`([^`\r\n]+)`');
// `~x~` and `~~x~~`, but never `~~~`. The site does strikethrough with one tilde too.
final _strike = RegExp(r'(?<!~)(~{1,2})(?!~)([^~\r\n]*?\S[^~\r\n]*?)\1(?!~)');
final _markdownLink = RegExp(r'\[((?:\\[\[\]]|[^\]\r\n])+)\]\(([^\s<>")]+)\)');
final _mentionToken = RegExp(r'(?<![A-Za-z0-9_])@[A-Za-z0-9_]+');
final _hashtagToken = RegExp(r'(?<![\p{L}\p{M}\p{N}_])#[\p{L}\p{M}\p{N}_]+', unicode: true);

bool _escapedAt(String body, int index) {
  var backslashes = 0;
  for (var at = index - 1; at >= 0 && body[at] == r'\'; at--) {
    backslashes++;
  }
  return backslashes.isOdd;
}

List<_Token> _tokenize(String body) {
  final tokens = <_Token>[];

  for (final match in _fence.allMatches(body)) {
    final language = match[1]!.trim().toLowerCase();
    tokens.add(_Token(
      language == 'latex' || language == 'tex' ? _Kind.latexFence : _Kind.codeFence,
      match.start,
      match.end,
      match[0]!,
      label: match[2],
    ));
  }
  for (final match in _inlineCode.allMatches(body)) {
    tokens.add(_Token(_Kind.code, match.start, match.end, match[0]!, label: match[1]));
  }
  tokens.addAll(_mathTokens(body, tokens));
  for (final match in _strike.allMatches(body)) {
    if (_escapedAt(body, match.start)) continue;
    tokens.add(_Token(_Kind.strike, match.start, match.end, match[0]!, label: match[2]));
  }
  for (final match in _markdownLink.allMatches(body)) {
    final url = markdownUrl(match[2]!);
    if (url == null) continue;
    tokens.add(_Token(
      _Kind.markdownLink,
      match.start,
      match.end,
      match[0]!,
      label: match[1]!.replaceAll(RegExp(r'\\([\[\]])'), r'$1'),
      url: url,
    ));
  }
  for (final match in matchUrls(body)) {
    tokens.add(_Token(_Kind.url, match.start, match.end, match.raw, url: match.url));
  }
  for (final match in _mentionToken.allMatches(body)) {
    tokens.add(_Token(_Kind.reference, match.start, match.end, match[0]!));
  }
  var hashtags = 0;
  for (final match in _hashtagToken.allMatches(body)) {
    if (hashtags++ == maxHashtagsPerPost) break;
    tokens.add(_Token(_Kind.reference, match.start, match.end, match[0]!));
  }

  tokens.sort((a, b) {
    final byStart = a.start.compareTo(b.start);
    return byStart != 0 ? byStart : _priority[a.kind]!.compareTo(_priority[b.kind]!);
  });
  return tokens;
}

/// A markdown link's destination may be schemeless (`[label](github.com/x)`), but
/// only if the whole destination is one URL and nothing else.
String? markdownUrl(String destination) {
  if (RegExp(r'^(?:https?|mailto):', caseSensitive: false).hasMatch(destination)) {
    return destination;
  }
  final matches = matchUrls(destination);
  if (matches.length != 1) return null;
  final match = matches.single;
  return match.start == 0 && match.end == destination.length ? match.url : null;
}

/// `$x$` inline and `$$x$$` display, skipping anything already inside code.
List<_Token> _mathTokens(String body, List<_Token> protected) {
  final tokens = <_Token>[];
  final ranges = protected
      .where((token) =>
          token.kind == _Kind.code ||
          token.kind == _Kind.codeFence ||
          token.kind == _Kind.latexFence)
      .toList()
    ..sort((a, b) => a.start.compareTo(b.start));

  int? skipTo(int index) {
    for (final range in ranges) {
      if (index >= range.start && index < range.end) return range.end;
    }
    return null;
  }

  var index = 0;
  while (index < body.length) {
    final skip = skipTo(index);
    if (skip != null) {
      index = skip;
      continue;
    }
    if (body[index] != r'$' || _escapedAt(body, index)) {
      index++;
      continue;
    }
    final display = index + 1 < body.length && body[index + 1] == r'$';
    final width = display ? 2 : 1;
    final contentStart = index + width;
    if (contentStart >= body.length ||
        (!display && RegExp(r'\s').hasMatch(body[contentStart]))) {
      index += width;
      continue;
    }

    var close = contentStart;
    while (close < body.length) {
      final inside = skipTo(close);
      if (inside != null) {
        close = inside;
        continue;
      }
      if (body[close] == r'$' &&
          !_escapedAt(body, close) &&
          (!display || (close + 1 < body.length && body[close + 1] == r'$'))) {
        final after = close + width;
        final validInlineClose = display ||
            (!RegExp(r'\s').hasMatch(body[close - 1]) &&
                !(after < body.length && RegExp(r'\d').hasMatch(body[after])));
        if (validInlineClose) break;
      }
      if (!display && (body[close] == '\n' || body[close] == '\r')) break;
      close++;
    }
    if (close >= body.length ||
        body[close] != r'$' ||
        (display && (close + 1 >= body.length || body[close + 1] != r'$'))) {
      index += width;
      continue;
    }

    final end = close + width;
    tokens.add(_Token(
      _Kind.math,
      index,
      end,
      body.substring(index, end),
      label: body.substring(contentStart, close),
      display: display,
    ));
    index = end;
  }
  return tokens;
}

// ---------------------------------------------------------------------------
// Inline spans
// ---------------------------------------------------------------------------

/// Inline tokens for one run of text, in order, with no gaps.
///
/// Fences are block-level and are never produced here — [markdownBlocks] pulls them
/// out first. A fence reaching this function is rendered as its own literal text.
List<BodyToken> tokenizeBody(String body) {
  final tokens = <BodyToken>[];
  var end = 0;

  void addText(String text) {
    if (text.isNotEmpty) tokens.add(PlainText(text));
  }

  for (final match in _tokenize(body)) {
    if (match.start < end) continue;
    addText(body.substring(end, match.start));
    switch (match.kind) {
      case _Kind.code:
      case _Kind.codeFence:
      case _Kind.latexFence:
        tokens.add(StyledText(match.label ?? match.raw, code: true));
      case _Kind.math:
        // Display maths inside a paragraph still renders inline; the block form is
        // produced by the block parser, which sees it on a line of its own.
        tokens.add(MathToken(match.label!));
      case _Kind.markdownLink:
        tokens.add(LinkToken(match.url!, label: match.label, raw: match.raw));
      case _Kind.strike:
        // The label can itself hold links and references.
        for (final inner in tokenizeBody(match.label!)) {
          tokens.add(switch (inner) {
            PlainText(:final text) => StyledText(text, strike: true),
            StyledText(:final text, :final bold, :final italic, :final code) =>
              StyledText(text, bold: bold, italic: italic, code: code, strike: true),
            final other => other,
          });
        }
      case _Kind.url:
        tokens.add(LinkToken(match.url!, label: shortLinkLabel(match.url!), raw: match.raw));
      case _Kind.reference:
        match.raw.startsWith('@')
            ? tokens.add(MentionToken(match.raw.substring(1)))
            : tokens.add(TagToken(match.raw.substring(1)));
    }
    end = match.end;
  }

  addText(body.substring(end));
  return tokens;
}

// ---------------------------------------------------------------------------
// Link labels
// ---------------------------------------------------------------------------

/// Where this app's own server lives, so a textlog.cc link can read as a path.
/// Set once at startup by `data/api.dart`; defaults to the public instance.
String linkOrigin = 'https://textlog.cc';

/// How the site labels a raw URL: a link to textlog itself reads as its path, and
/// anything else drops the scheme and a leading `www.`.
///
/// `https://textlog.cc/post/12` -> `/post/12`
/// `https://textlog.cc`         -> `textlog.cc`
/// `https://www.example.com/a`  -> `example.com/a`
String shortLinkLabel(String url) {
  final origin = linkOrigin.replaceFirst(RegExp(r'/$'), '');
  if (url.startsWith(origin)) {
    final relative = url.substring(origin.length);
    if (relative.isEmpty || relative == '/') return Uri.parse(origin).host;
    return relative.startsWith('/') ? relative : '/$relative';
  }
  return url
      .replaceFirst(RegExp(r'^[a-z]+://', caseSensitive: false), '')
      .replaceFirst(RegExp(r'^www\.', caseSensitive: false), '')
      .replaceFirst(RegExp(r'/$'), '');
}

/// Where the host ends and the path begins, so the path can be allowed to break
/// mid-word while the host is kept whole — `.raw-link-rest` on the site.
int linkBreakPoint(String label) {
  final at = label.indexOf('/');
  return at < 0 ? label.length : at;
}

/// Port of the server's `fmt` — the compact "3h" / "2mo" stamp.
String relativeTime(DateTime time, {DateTime? now}) {
  final seconds = (now ?? DateTime.now()).difference(time).inSeconds;
  if (seconds < 60) return '${seconds < 1 ? 1 : seconds}s';
  final minutes = seconds ~/ 60;
  if (minutes < 60) return '${minutes}m';
  final hours = minutes ~/ 60;
  if (hours < 24) return '${hours}h';
  final days = hours ~/ 24;
  if (days < 30) return '${days}d';
  final months = days ~/ 30;
  if (months < 12) return '${months}mo';
  return '${days ~/ 365}y';
}

/// `isAsciiArt` kept as a name the widgets already use.
bool isAsciiArt(String body) => containsAsciiArt(body);
