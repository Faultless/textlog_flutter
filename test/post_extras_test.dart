import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/post_tile.dart';

Post post({
  String body = 'hello',
  String? executionOutput,
  PostLocation? location,
}) => Post(
  id: 7,
  body: body,
  createdAt: DateTime.now(),
  parentId: null,
  replyCount: 0,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/7'),
  author: Author(handle: 'a', url: Uri.parse('https://textlog.cc/u/a')),
  executionOutput: executionOutput,
  location: location,
);

Future<void> show(WidgetTester tester, Post subject) async {
  SharedPreferences.setMockInitialValues({});
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) => Scaffold(body: SingleChildScrollView(child: PostTile(subject))),
      ),
    ],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp.router(theme: textlogTheme(Palette.dark), routerConfig: router),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  group('a #exec post', () {
    testWidgets('shows what the server ran', (tester) async {
      await show(tester, post(body: '#exec\n```js\nconsole.log(2)\n```',
          executionOutput: '2\n'));
      expect(find.text('2'), findsOneWidget);
    });

    testWidgets('clipped to the same lines the site shows', (tester) async {
      final output = [for (var i = 1; i <= 40; i++) 'line $i'].join('\n');
      await show(tester, post(executionOutput: output));

      expect(find.textContaining('line 1\n'), findsOneWidget);
      expect(find.textContaining('line 40'), findsOneWidget);
      expect(find.textContaining('line 20'), findsNothing);
    });

    testWidgets('and nothing at all when it printed nothing', (tester) async {
      await show(tester, post(executionOutput: '   \n'));
      // No empty box: a program that printed nothing has nothing to show.
      expect(find.byType(Container), findsWidgets);
      expect(find.textContaining('  '), findsNothing);
    });
  });

  group('a #map post', () {
    final berlin = PostLocation(
      query: 'Kreuzberg',
      displayName: 'Kreuzberg, Berlin, Germany',
      url: Uri.parse('https://maps.google.com/?q=52.5,13.4'),
      preview: const LinkPreview(
        imageUrl: 'https://textlog.cc/i/map.png',
        title: 'Kreuzberg',
        description: 'Berlin, Germany',
      ),
    );

    testWidgets('shows the place the server found', (tester) async {
      await show(tester, post(body: '#map\nKreuzberg', location: berlin));
      expect(find.text('Kreuzberg'), findsWidgets);
      expect(find.textContaining('Berlin'), findsWidgets);
    });

    testWidgets('and a post without one draws no card', (tester) async {
      await show(tester, post(body: 'no map here'));
      expect(find.textContaining('Berlin'), findsNothing);
    });
  });

  group('a code fence', () {
    testWidgets('is coloured for the two languages the site colours', (tester) async {
      await show(tester, post(body: '```js\nconst x = 1\n```'));

      final colours = <Color?>{};
      for (final widget in tester.widgetList<RichText>(find.byType(RichText))) {
        widget.text.visitChildren((span) {
          if (span is TextSpan && span.text != null) colours.add(span.style?.color);
          return true;
        });
      }

      expect(colours, contains(Palette.dark.accentDark), reason: 'the keyword');
      expect(colours, contains(Palette.dark.selfInk), reason: 'the number');
    });

    testWidgets('and left alone for the ones it does not', (tester) async {
      await show(tester, post(body: '```rust\nfn main() {}\n```'));
      expect(find.textContaining('fn main'), findsOneWidget);
    });
  });

  test('a profile carries what it pinned', () {
    // `#pin` puts a note at the top of a profile. The API hands it back on the
    // profile rather than sorting it into the notes list, so the app draws it above
    // the list and leaves it out of it — see ProfileScreen.
    final profile = Profile.fromJson({
      'handle': 'a',
      'bio': '',
      'created_at': '2026-08-26T08:00:00.000Z',
      'post_count': 1,
      'follower_count': 0,
      'url': 'https://textlog.cc/u/a',
      'pinned_note': {
        'id': 11,
        'body': 'read this first',
        'created_at': '2026-08-26T08:00:00.000Z',
        'parent_id': null,
        'reply_count': 0,
        'tags': ['pin'],
        'mentions': <String>[],
        'url': 'https://textlog.cc/post/11',
        'author': {'handle': 'a', 'url': 'https://textlog.cc/u/a'},
      },
      'pinned_reply': null,
    });

    expect(profile.pinnedNote?.id, 11);
    expect(profile.pinnedReply, isNull);
  });

  test('the fields come off the wire', () {
    final parsed = Post.fromJson({
      'id': 7,
      'body': 'x',
      'created_at': '2026-08-26T08:00:00.000Z',
      'parent_id': null,
      'reply_count': 0,
      'tags': <String>[],
      'mentions': <String>[],
      'url': 'https://textlog.cc/post/7',
      'author': {'handle': 'a', 'url': 'https://textlog.cc/u/a'},
      'execution_output': 'hi\n',
      'location': {
        'query': 'Kreuzberg',
        'latitude': 52.5,
        'longitude': 13.4,
        'displayName': 'Kreuzberg, Berlin, Germany',
        'url': 'https://maps.google.com/?q=52.5,13.4',
        'preview': {'imageUrl': 'https://textlog.cc/i/map.png', 'title': 'Kreuzberg'},
      },
    });

    expect(parsed.executionOutput, 'hi\n');
    expect(parsed.location?.displayName, 'Kreuzberg, Berlin, Germany');
    expect(parsed.location?.url.host, 'maps.google.com');
    // An edit must not drop either of them.
    expect(parsed.copyWith(body: 'y').executionOutput, 'hi\n');
    expect(parsed.copyWith(body: 'y').location?.query, 'Kreuzberg');
  });
}
