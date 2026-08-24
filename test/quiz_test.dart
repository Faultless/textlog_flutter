import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/polls.dart';
import 'package:textlog/core/post_context.dart';

const quiz = 'Which planet has the shortest day? #quiz\n'
    'Earth\n'
    'Mars\n'
    '> Jupiter\n'
    'Saturn\n'
    '\n'
    'a day on Jupiter is only about *9 hours 56 minutes* long';

void main() {
  group('a quiz in the body', () {
    test('reads its question, options, answer and explanation', () {
      final parsed = parsePoll(quiz)!;
      expect(parsed.isQuiz, isTrue);
      expect(parsed.question, 'Which planet has the shortest day?');
      expect(parsed.options, ['Earth', 'Mars', 'Jupiter', 'Saturn']);
      expect(parsed.correctIndex, 2);
      expect(parsed.explanation, contains('9 hours 56 minutes'));
    });

    test('strips everything after the marker from what renders', () {
      // The options and the explanation are part of the body. Rendered as text they
      // would give the answer away above the quiz.
      expect(pollDisplayBody(quiz), 'Which planet has the shortest day? #quiz');
    });

    test('needs exactly one marked answer', () {
      expect(parsePoll('q #quiz\na\nb'), isNull, reason: 'none marked');
      expect(parsePoll('q #quiz\n> a\n> b'), isNull, reason: 'two marked');
      expect(parsePoll('q #quiz\n> a\nb'), isNotNull);
    });

    test('an explanation is optional', () {
      final parsed = parsePoll('q #quiz\n> a\nb')!;
      expect(parsed.explanation, isNull);
      expect(parsed.options, ['a', 'b']);
    });

    test('a poll still has no answer and keeps every line as an option', () {
      // A blank line does not end a poll's options the way it ends a quiz's.
      final parsed = parsePoll('q #poll\na\n\nb')!;
      expect(parsed.isQuiz, isFalse);
      expect(parsed.correctIndex, isNull);
      expect(parsed.options, ['a', 'b']);
    });
  });

  group('a quiz from the API', () {
    Map<String, dynamic> poll({
      String kind = 'quiz',
      String? expiresAt,
      bool voted = false,
      bool? correct,
      String? explanation,
    }) => {
      'options': [
        {'id': 1, 'label': 'Earth', 'votes': voted ? 1 : null, 'selected': voted,
          'correct': correct},
        {'id': 2, 'label': 'Jupiter', 'votes': voted ? 3 : null, 'selected': false,
          'correct': correct == null ? null : !correct},
      ],
      'kind': kind,
      'explanation': explanation,
      'total_votes': voted ? 4 : null,
      'expired': false,
      'expires_at': expiresAt,
      'viewer_voted': voted,
    };

    test('decodes with no expiry at all', () {
      // This is what a live quiz post looks like, and reading `expires_at` as a
      // required string threw — taking down the whole feed page that carried it.
      final parsed = Poll.fromJson(poll());
      expect(parsed.isQuiz, isTrue);
      expect(parsed.expiresAt, isNull);
      expect(parsed.expired, isFalse);
      expect(parsed.open, isTrue);
    });

    test('a poll still carries its deadline', () {
      final parsed = Poll.fromJson(
        poll(kind: 'poll', expiresAt: '2026-08-24T10:00:00.000Z'),
      );
      expect(parsed.isQuiz, isFalse);
      expect(parsed.expiresAt, isNotNull);
    });

    test('withholds the answer until the reader has picked', () {
      final parsed = Poll.fromJson(poll());
      expect(parsed.answer, isNull);
      expect(parsed.gotItRight, isNull);
      expect(parsed.explanation, isNull);
    });

    test('says which one was right, and whether that is the one you picked', () {
      final right = Poll.fromJson(poll(voted: true, correct: true, explanation: 'why'));
      expect(right.answer?.label, 'Earth');
      expect(right.gotItRight, isTrue);
      expect(right.explanation, 'why');

      final wrong = Poll.fromJson(poll(voted: true, correct: false));
      expect(wrong.answer?.label, 'Jupiter');
      expect(wrong.gotItRight, isFalse);
    });

    test('a poll never claims a verdict', () {
      final parsed = Poll.fromJson(poll(kind: 'poll', voted: true));
      expect(parsed.gotItRight, isNull);
      expect(parsed.answer, isNull);
    });
  });

  group('what the meta line says', () {
    Post subject(String body, {Poll? poll}) => Post(
      id: 1,
      body: body,
      createdAt: DateTime(2026, 8, 8),
      parentId: null,
      replyCount: 0,
      tags: const [],
      mentions: const [],
      url: Uri.parse('https://textlog.cc/post/1'),
      author: Author(handle: 'a', url: Uri.parse('https://textlog.cc/u/a')),
      poll: poll,
    );

    Poll parsed({required String kind}) => Poll.fromJson({
      'options': [
        {'id': 1, 'label': 'a', 'votes': null, 'selected': false},
        {'id': 2, 'label': 'b', 'votes': null, 'selected': false},
      ],
      'kind': kind,
      'total_votes': null,
      'expired': false,
      'expires_at': kind == 'quiz' ? null : '2026-08-24T10:00:00.000Z',
      'viewer_voted': false,
    });

    test('a quiz is announced as a quiz', () {
      // The site words it `created a ${kind}`. Calling a quiz a poll misdescribes
      // what tapping it does.
      expect(postContextOf(subject('q #quiz', poll: parsed(kind: 'quiz'))).label,
          'created a quiz');
    });

    test('a poll is still a poll', () {
      expect(postContextOf(subject('q #poll', poll: parsed(kind: 'poll'))).label,
          'created a poll');
    });

    test('and the body decides when the server has not materialised one', () {
      expect(postContextOf(subject('q #quiz\n> a\nb')).label, 'created a quiz');
      expect(postContextOf(subject('q #poll\na\nb')).label, 'created a poll');
    });
  });
}
