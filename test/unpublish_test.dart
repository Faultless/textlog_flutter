import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/session.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/post_actions.dart';
import 'package:textlog/ui/widgets/post_tile.dart';

final _session = Session(
  token: 'tok',
  expiresAt: DateTime(2027),
  account: const Account(handle: 'me', bio: '', canPost: true),
);

class FakeSession extends SessionNotifier {
  @override
  Future<Session?> build() async => _session;
}

Post mine({int? parent}) => Post(
  id: 7,
  body: 'my post',
  createdAt: DateTime(2026, 8, 26),
  parentId: parent,
  replyCount: 0,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/7'),
  author: Author(handle: 'me', url: Uri.parse('https://textlog.cc/u/me')),
);

/// Renders the post's own card and reports the requests it makes and where it goes.
Future<({List<String> calls, List<String> visited})> show(
  WidgetTester tester,
  Post post, {
  bool isSubject = false,
}) async {
  SharedPreferences.setMockInitialValues({});
  final calls = <String>[];
  final visited = <String>[];
  final router = GoRouter(
    initialLocation: '/post/7',
    routes: [
      for (final path in ['/post/:id', '/drafts', '/'])
        GoRoute(
          path: path,
          builder: (_, state) {
            visited.add(state.uri.path);
            return Scaffold(
              body: SingleChildScrollView(
                child: PostTile(post, isSubject: isSubject),
              ),
            );
          },
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
            calls.add('${request.method} ${request.url.path}');
            return http.Response(
              jsonEncode({
                'data': {
                  'id': 3,
                  'body': 'my post',
                  'parent_id': null,
                  'created_at': '2026-08-26T08:00:00.000Z',
                  'updated_at': '2026-08-26T08:00:00.000Z',
                },
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
  visited.clear();
  return (calls: calls, visited: visited);
}

void main() {
  group('moving a post back to drafts', () {
    testWidgets('is offered on your own post, beside edit and delete',
        (tester) async {
      await show(tester, mine());
      await tester.tap(find.byType(PostMenu));
      await tester.pumpAndSettle();

      expect(find.text('move to drafts'), findsOneWidget);
      expect(find.text('edit'), findsOneWidget);
      expect(find.text('delete'), findsOneWidget);
    });

    testWidgets('asks the server and says so, with nothing to confirm',
        (tester) async {
      // Nothing is lost — the words go to the drafts list — so a confirmation
      // dialog would be asking permission for something reversible.
      final result = await show(tester, mine());
      await tester.tap(find.byType(PostMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('move to drafts'));
      await tester.pumpAndSettle();

      expect(result.calls, contains('POST /api/v1/posts/7/unpublish'));
      expect(find.text('Moved to drafts.'), findsOneWidget);
    });

    testWidgets('leaves the page that was about it', (tester) async {
      // Standing on a post that is no longer published is a dead end.
      final result = await show(tester, mine(), isSubject: true);
      await tester.tap(find.byType(PostMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('move to drafts'));
      await tester.pumpAndSettle();

      expect(result.visited, contains('/drafts'));
    });

    testWidgets('a reply goes back to the post it answered', (tester) async {
      final result = await show(tester, mine(parent: 4), isSubject: true);
      await tester.tap(find.byType(PostMenu));
      await tester.pumpAndSettle();
      await tester.tap(find.text('move to drafts'));
      await tester.pumpAndSettle();

      expect(result.visited, contains('/post/4'));
      expect(result.visited, isNot(contains('/drafts')));
    });
  });
}
