import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/media.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/link_preview_view.dart';

Post post(String body, {Map<String, LinkPreview> previews = const {}}) => Post(
  id: 1,
  body: body,
  createdAt: DateTime(2026, 8, 8),
  parentId: null,
  replyCount: 0,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/1'),
  author: Author(handle: 'a', url: Uri.parse('https://textlog.cc/u/a')),
  linkPreviews: previews,
);

void main() {
  group('a voice clip link', () {
    test('is recognised on either host', () {
      expect(vocarooId('https://voca.ro/140JOkFnkmRv'), '140JOkFnkmRv');
      expect(vocarooId('https://vocaroo.com/abc123'), 'abc123');
      expect(vocarooId('https://www.voca.ro/xyz/'), 'xyz');
    });

    test('and nothing else is', () {
      expect(vocarooId('https://voca.ro/'), isNull, reason: 'no id');
      expect(vocarooId('https://voca.ro/a/b'), isNull, reason: 'not a clip path');
      expect(vocarooId('https://example.com/abc'), isNull);
      // A host that merely ends in the real one is a different site.
      expect(vocarooId('https://voca.ro.evil.example/abc'), isNull);
    });

    test('is found in a body', () {
      expect(
        audioLinksIn('listen https://voca.ro/1abc and https://example.com').toList(),
        ['https://voca.ro/1abc'],
      );
    });
  });

  group('the card', () {
    Future<void> show(WidgetTester tester, Post subject) async {
      SharedPreferences.setMockInitialValues({});
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(body: LinkPreviews(subject)),
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(
        MaterialApp.router(theme: textlogTheme(Palette.dark), routerConfig: router),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('says a clip is a clip, with no preview from the server',
        (tester) async {
      // Vocaroo drives its own player off the link, so the server sends no preview
      // for one. Without this it renders as a bare URL like any other.
      await show(tester, post('hear this https://voca.ro/1abc'));

      expect(find.textContaining('voice clip'), findsOneWidget);
    });

    testWidgets('a real preview still comes first', (tester) async {
      await show(
        tester,
        post(
          'https://voca.ro/1abc',
          previews: {
            'https://example.com': const LinkPreview(imageUrl: '', title: 'A page'),
          },
        ),
      );

      expect(find.text('A page'), findsOneWidget);
      expect(find.textContaining('voice clip'), findsNothing);
    });

    testWidgets('an ordinary post gets no card', (tester) async {
      await show(tester, post('nothing linked here'));
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.textContaining('voice clip'), findsNothing);
    });
  });
}
