import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/ui/screens/thread.dart';
import 'package:textlog/ui/theme.dart';

Map<String, dynamic> post(int id, {required String body, int? parent, int replies = 0}) => {
  'id': id,
  'body': body,
  'created_at': '2026-08-23T10:46:32.000Z',
  'parent_id': parent,
  'reply_count': replies,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'author': {'handle': 'stagas', 'url': 'https://textlog.cc/u/stagas'},
};

/// The whole thread page for post 1, served the bodies given.
Future<void> show(WidgetTester tester, String subject, {String? reply}) async {
  SharedPreferences.setMockInitialValues({});
  final router = GoRouter(
    initialLocation: '/post/1',
    routes: [
      GoRoute(
        path: '/post/:id',
        builder: (_, state) => ThreadScreen(id: int.parse(state.pathParameters['id']!)),
      ),
    ],
  );
  addTearDown(router.dispose);

  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            final utf8Json = {'content-type': 'application/json; charset=utf-8'};
            final body = request.url.path.endsWith('/replies')
                ? {
                    'data': [
                      if (reply != null) post(2, body: reply, parent: 1),
                    ],
                    'pagination': {'next_cursor': null},
                  }
                : {'data': post(1, body: subject, replies: reply == null ? 0 : 1)};
            return http.Response(jsonEncode(body), 200, headers: utf8Json);
          }),
        ),
      ],
      child: MaterialApp.router(theme: textlogTheme(Palette.dark), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('a thread whose post carries a code fence still draws', (tester) async {
    // A live post did exactly this and the page came up empty: one layout throw
    // inside the body took down the post, the replies and the reply form with it.
    await show(
      tester,
      'you can now microblog about your to-dos!\n\n```\nsomething #todo list\n[x] done\n```',
      reply: 'I have this in my #Emacs config:\n\n```\n(setq x t)\n```',
    );

    expect(tester.takeException(), isNull);
    expect(find.textContaining('microblog'), findsOneWidget);
    expect(find.textContaining('(setq x t)'), findsOneWidget);
    expect(find.text('1 reply'), findsOneWidget);
  });

  testWidgets('and one without replies says so rather than showing nothing',
      (tester) async {
    await show(tester, 'just a line');

    expect(tester.takeException(), isNull);
    expect(find.text('No replies yet.'), findsOneWidget);
  });
}
