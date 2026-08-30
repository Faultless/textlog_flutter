import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/data/api.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/session.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/activity_view.dart';

final _session = Session(
  token: 'tok',
  expiresAt: DateTime(2027),
  account: const Account(handle: 'me', bio: '', canPost: true),
);

class FakeSession extends SessionNotifier {
  @override
  Future<Session?> build() async => _session;
}

Map<String, dynamic> row(int n) => {
  'id': 'e$n',
  'type': 'post',
  'created_at': '2026-08-08T08:00:00.000Z',
  'unread': true,
  'payload': {
    'id': n,
    'body': 'post $n',
    'created_at': '2026-08-08T08:00:00.000Z',
    'parent_id': null,
    'reply_count': 0,
    'tags': <String>[],
    'mentions': <String>[],
    'url': 'https://textlog.cc/post/$n',
    'author': {'handle': 'a', 'url': 'https://textlog.cc/u/a'},
  },
};

/// The to-me feed with [count] unread rows, reporting every id sent to `/read`.
Future<List<String>> show(WidgetTester tester, int count) async {
  SharedPreferences.setMockInitialValues({});
  final marked = <String>[];
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => const Scaffold(body: ActivityView(ActivityScope.toMe)),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        sessionProvider.overrideWith(FakeSession.new),
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            if (request.method == 'POST') {
              final body = jsonDecode(request.body) as Map<String, dynamic>;
              marked.addAll((body['activity_ids'] as List).cast<String>());
              return http.Response('{"data":{}}', 200);
            }
            return http.Response(
              jsonEncode({
                'data': [for (var n = 1; n <= count; n++) row(n)],
                'has_unread': true,
                'pagination': {'next_cursor': null},
              }),
              200,
              headers: {'content-type': 'application/json; charset=utf-8'},
            );
          }),
        ),
      ],
      child: MaterialApp.router(theme: textlogTheme(Palette.dark), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
  await flushReads(tester);
  return marked;
}

/// Let the batched ids go out. Marking is optimistic and the request is held for a
/// moment so a fling costs one of them — see ReadQueue — which a test has to wait
/// out before it can look at what the server was told.
Future<void> flushReads(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 500));
  await tester.pumpAndSettle();
}

void main() {
  group('reading marks it read', () {
    testWidgets('the rows on screen when the tab opens', (tester) async {
      // Scrolling through everything used to leave every dot in place until you
      // pressed "mark all as read" — a chore you had already done by reading.
      final marked = await show(tester, 3);

      expect(marked, isNotEmpty, reason: 'the first screenful counts too');
      expect(marked, contains('e1'));
    });

    testWidgets('and the rows further down once they are scrolled to',
        (tester) async {
      final marked = await show(tester, 40);
      final atOpen = {...marked};
      expect(atOpen, isNot(contains('e40')), reason: 'nowhere near the screen yet');

      await tester.fling(find.byType(CustomScrollView), const Offset(0, -4000), 800);
      await tester.pumpAndSettle();
      await flushReads(tester);

      expect(marked.length, greaterThan(atOpen.length));
    });

    testWidgets('each row only once, however much you scroll', (tester) async {
      final marked = await show(tester, 12);
      for (var i = 0; i < 3; i++) {
        await tester.fling(find.byType(CustomScrollView), const Offset(0, -300), 600);
        await tester.pumpAndSettle();
        await tester.fling(find.byType(CustomScrollView), const Offset(0, 300), 600);
        await tester.pumpAndSettle();
        await flushReads(tester);
      }

      // The notifier is optimistic, so without a guard a row that has stopped being
      // unread locally would be re-sent on every scroll that passed it.
      expect(marked.length, marked.toSet().length, reason: 'no id sent twice');
    });

    testWidgets('an empty feed asks the server for nothing', (tester) async {
      final marked = await show(tester, 0);
      expect(marked, isEmpty);
    });
  });
}
