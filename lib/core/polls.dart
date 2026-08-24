/// Port of the server's `src/polls.ts` parsing half.
///
/// A poll is not a field on the API's post shape — it is *encoded in the body*: a
/// line ending in `#poll` (or `#quiz`), then one option per line. So the app has to
/// parse it for two reasons. Without it those option lines render as body text, which
/// is simply wrong; and with it the options can be drawn as a poll.
///
/// The API carries polls now — options, tally and all — so this is no longer where
/// the app learns what a poll *is*. What it is still needed for is the body: the
/// option lines are part of it, and they must be stripped from what renders above the
/// poll or the reader sees them twice.
library;

const pollLifetime = Duration(hours: 24);

/// `#poll` or `#quiz`, at the end of a line either way.
final _marker = RegExp(r'(?:^|\s)#(?:poll|quiz)\s*$', caseSensitive: false);
final _markerTail = RegExp(r'#(poll|quiz)\s*$', caseSensitive: false);

/// A quiz marks its right answer with a leading `>` and may follow the options with a
/// blank line and an explanation.
final _answer = RegExp(r'^>\s+');

final class PollBody {
  const PollBody({
    required this.question,
    required this.options,
    this.isQuiz = false,
    this.correctIndex,
    this.explanation,
  });

  final String question;
  final List<String> options;
  final bool isQuiz;

  /// Which option the author marked right. Always set on a quiz — a quiz with none,
  /// or with more than one, is not a quiz at all and does not parse.
  final int? correctIndex;

  final String? explanation;
}

/// The server's rules exactly: a `#poll` or `#quiz` line, a non-empty question before
/// it, and two to eight distinct options after it. A quiz needs exactly one option
/// marked `>`. Anything else is not a poll.
PollBody? parsePoll(String body) {
  final lines = body.split('\n');
  final marker = lines.indexWhere(_marker.hasMatch);
  if (marker < 0) return null;

  final markerLine = lines[marker];
  final tail = _markerTail.firstMatch(markerLine)!;
  final isQuiz = tail.group(1)!.toLowerCase() == 'quiz';
  final question = [
    ...lines.sublist(0, marker),
    markerLine.substring(0, tail.start),
  ].join('\n').trim();

  // On a quiz the first blank line ends the options and starts the explanation. A
  // poll has no such break: every remaining line is an option.
  final rest = lines.sublist(marker + 1);
  final separator = isQuiz ? rest.indexWhere((line) => line.trim().isEmpty) : -1;
  final answerLines = (separator < 0 ? rest : rest.sublist(0, separator))
      .map((option) => option.trim())
      .where((option) => option.isNotEmpty)
      .toList();
  final explanation =
      separator < 0 ? '' : rest.sublist(separator + 1).join('\n').trim();

  final correct = [
    for (final line in answerLines) isQuiz && _answer.hasMatch(line),
  ];
  final options = [
    for (final line in answerLines)
      isQuiz ? line.replaceFirst(_answer, '').trim() : line,
  ];

  if (question.isEmpty ||
      options.length < 2 ||
      options.length > 8 ||
      options.toSet().length != options.length) {
    return null;
  }
  if (isQuiz && correct.where((right) => right).length != 1) return null;

  return PollBody(
    question: question,
    options: options,
    isQuiz: isQuiz,
    correctIndex: isQuiz ? correct.indexOf(true) : null,
    explanation: isQuiz && explanation.isNotEmpty ? explanation : null,
  );
}

/// The body with the option lines removed, which is what the site renders above the
/// poll. Bodies without a poll come back untouched.
String pollDisplayBody(String body) {
  if (parsePoll(body) == null) return body;
  final lines = body.split('\n');
  final marker = lines.indexWhere(_marker.hasMatch);
  return lines.sublist(0, marker + 1).join('\n').trim();
}

/// Polls close 24 hours after the post was written. Quizzes never close — there is no
/// tally to settle, only an answer. The API reports this directly on the poll now;
/// this stays for the case where a body has a poll the server has not materialised.
bool pollClosed(DateTime createdAt, {DateTime? now}) =>
    (now ?? DateTime.now()).difference(createdAt) >= pollLifetime;
