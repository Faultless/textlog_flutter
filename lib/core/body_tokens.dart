/// Port of the server's `linkify` (src/utils.ts) so bodies render identically here.
/// Pure in, pure out — the widget layer only decides how each token looks.
library;

sealed class BodyToken {
  const BodyToken();
}

final class PlainText extends BodyToken {
  const PlainText(this.text);
  final String text;
}

final class LinkToken extends BodyToken {
  const LinkToken(this.url, {this.label});
  final String url;

  /// Set only for a markdown `[label](url)`; otherwise the URL is its own label.
  final String? label;

  String get text => label ?? url;
}

/// Emphasised run of plain text. Only produced when markdown rendering is on.
final class StyledText extends BodyToken {
  const StyledText(this.text, {this.bold = false, this.italic = false, this.strike = false});

  final String text;
  final bool bold;
  final bool italic;
  final bool strike;
}

final class MentionToken extends BodyToken {
  const MentionToken(this.handle);
  final String handle;
}

final class TagToken extends BodyToken {
  const TagToken(this.tag);
  final String tag;
}

final _tokens = RegExp(
  r'https?://[^\s<>"]+|(?<![A-Za-z0-9_])[@#][A-Za-z0-9_]+',
  caseSensitive: false,
);

final _trailingPunctuation = RegExp(r'[.,!?;:]+$');

List<BodyToken> tokenizeBody(String body) {
  final tokens = <BodyToken>[];
  var end = 0;

  void addText(String text) {
    if (text.isNotEmpty) tokens.add(PlainText(text));
  }

  for (final match in _tokens.allMatches(body)) {
    addText(body.substring(end, match.start));
    final token = match[0]!;

    if (token.toLowerCase().startsWith('http')) {
      // A URL at the end of a sentence must not swallow the full stop.
      final url = token.replaceFirst(_trailingPunctuation, '');
      tokens.add(LinkToken(url));
      addText(token.substring(url.length));
    } else if (token.startsWith('@')) {
      tokens.add(MentionToken(token.substring(1)));
    } else {
      tokens.add(TagToken(token.substring(1)));
    }
    end = match.end;
  }

  addText(body.substring(end));
  return tokens;
}

/// The site's hashtags rule, without the mention lookbehind: `/#([A-Za-z0-9_]+)/g`.
final _hashtag = RegExp(r'#([A-Za-z0-9_]+)');

/// Port of the server's `containsAsciiArt`. Drawing is opt-in by hashtag, and those
/// posts render with compact line spacing — `line-height: 1.15` against the usual
/// 1.65 — because art drawn on a character grid falls apart when the rows are spread.
bool isAsciiArt(String body) => _hashtag.allMatches(body).any((match) {
  final tag = match[1]!.toLowerCase();
  return tag == 'ascii' || tag == 'ascii_art';
});

/// Port of the server's `fmt` — the compact "3h" / "2mo" stamp shown on every post.
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
