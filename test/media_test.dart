import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/media.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/link_preview_view.dart';
import 'package:textlog/ui/widgets/voice_clip.dart';

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

    test('streams from textlog, never from Vocaroo', () {
      // The whole point of the proxy: playing a clip tells Vocaroo nothing about
      // who listened.
      expect(
        audioStreamUrl('https://voca.ro/1abc', origin: 'https://textlog.cc'),
        'https://textlog.cc/media/vocaroo/1abc',
      );
      // A self-hosted instance proxies its own readers.
      expect(
        audioStreamUrl('https://vocaroo.com/xyz', origin: 'https://tl.example/'),
        'https://tl.example/media/vocaroo/xyz',
      );
      expect(audioStreamUrl('https://example.com/a', origin: 'https://textlog.cc'),
          isNull);
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
        ProviderScope(
          child: MaterialApp.router(
            theme: textlogTheme(Palette.dark),
            routerConfig: router,
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('becomes a player, with no preview from the server', (tester) async {
      // Vocaroo drives its own player off the link, so the server sends no preview
      // for one. Without recognising the link it renders as a bare URL like any other.
      await show(tester, post('hear this https://voca.ro/1abc'));

      expect(find.byType(VoiceClip), findsOneWidget);
      expect(find.text('voice clip'), findsOneWidget);
      expect(find.text('▶'), findsOneWidget, reason: 'offers to play it');
    });

    testWidgets('is given the proxy to play, not the page it was linked from',
        (tester) async {
      // The bug this guards: the link identifies the clip, the proxy is where the
      // bytes are, and handing the link to the player asks it to decode Vocaroo's
      // *web page* — which fails as "no extractor could read the stream", reading
      // like a broken clip rather than the mix-up it is.
      await show(tester, post('https://voca.ro/1abc'));

      final clip = tester.widget<VoiceClip>(find.byType(VoiceClip));
      expect(clip.url, 'https://voca.ro/1abc');
      expect(clip.streamUrl, 'https://textlog.cc/media/vocaroo/1abc');
      expect(clip.streamUrl, isNot(clip.url));
    });

    testWidgets('rendering one needs no audio engine', (tester) async {
      // Nothing touches the player until it is pressed, which is what keeps a card
      // scrolling past from holding a decoder open — and what lets this test run
      // with no platform channel at all.
      await show(tester, post('https://voca.ro/1abc'));

      expect(tester.takeException(), isNull);
      expect(find.text('❚❚'), findsNothing);
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
      expect(find.byType(VoiceClip), findsNothing);
    });

    testWidgets('an ordinary post gets no card', (tester) async {
      await show(tester, post('nothing linked here'));
      expect(find.byType(SizedBox), findsWidgets);
      expect(find.byType(VoiceClip), findsNothing);
    });
  });
}
