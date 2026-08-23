/// Port of the server's `src/polls.ts` parsing half.
///
/// A poll is not a field on the API's post shape — it is *encoded in the body*: a
/// line ending in `#poll`, then one option per line. So the app has to parse it for
/// two reasons. Without it those option lines render as body text, which is simply
/// wrong; and with it the options can be drawn as a poll.
///
/// The API carries polls now — options, tally and all — so this is no longer where
/// the app learns what a poll *is*. What it is still needed for is the body: the
/// option lines are part of it, and they must be stripped from what renders above the
/// poll or the reader sees them twice.
library;

const pollLifetime = Duration(hours: 24);

final _marker = RegExp(r'(?:^|\s)#poll\s*$', caseSensitive: false);

final class PollBody {
  const PollBody({required this.question, required this.options});

  final String question;
  final List<String> options;
}

/// The server's rules exactly: a `#poll` line, a non-empty question before it, and
/// two to eight distinct options after it. Anything else is not a poll.
PollBody? parsePoll(String body) {
  final lines = body.split('\n');
  final marker = lines.indexWhere(_marker.hasMatch);
  if (marker < 0) return null;

  final markerLine = lines[marker];
  final markerStart = markerLine.toLowerCase().lastIndexOf('#poll');
  final question = [
    ...lines.sublist(0, marker),
    markerLine.substring(0, markerStart),
  ].join('\n').trim();

  final options = lines
      .sublist(marker + 1)
      .map((option) => option.trim())
      .where((option) => option.isNotEmpty)
      .toList();

  if (question.isEmpty ||
      options.length < 2 ||
      options.length > 8 ||
      options.toSet().length != options.length) {
    return null;
  }
  return PollBody(question: question, options: options);
}

/// The body with the option lines removed, which is what the site renders above the
/// poll. Bodies without a poll come back untouched.
String pollDisplayBody(String body) {
  if (parsePoll(body) == null) return body;
  final lines = body.split('\n');
  final marker = lines.indexWhere(_marker.hasMatch);
  return lines.sublist(0, marker + 1).join('\n').trim();
}

/// Polls close 24 hours after the post was written. The API reports this directly on
/// the poll now; this stays for the case where a body has a poll the server has not
/// materialised.
bool pollClosed(DateTime createdAt, {DateTime? now}) =>
    (now ?? DateTime.now()).difference(createdAt) >= pollLifetime;
