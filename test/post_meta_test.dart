import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/session.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/post_meta.dart';

final signedIn = Session(
  token: 'token',
  expiresAt: DateTime(2030),
  account: const Account(handle: 'me', bio: '', canPost: true),
);

class FakeSession extends SessionNotifier {
  FakeSession(this.session);

  final Session? session;

  @override
  Future<Session?> build() async => session;
}

Widget app(Widget child, {Session? session}) => ProviderScope(
  key: UniqueKey(),
  overrides: [sessionProvider.overrideWith(() => FakeSession(session))],
  child: MaterialApp(
    theme: textlogTheme(Palette.dark),
    home: Scaffold(body: child),
  ),
);

void main() {
  testWidgets('your own handle is inked differently from everyone else', (tester) async {
    await tester.pumpWidget(
      app(const Row(children: [HandleLink('me'), HandleLink('someone')]), session: signedIn),
    );
    await tester.pump();

    final mine = tester.widget<Text>(find.text('@me')).style!.color;
    final theirs = tester.widget<Text>(find.text('@someone')).style!.color;

    expect(mine, Palette.dark.selfInk);
    expect(theirs, Palette.dark.ink);
    expect(mine, isNot(theirs));
  });

  testWidgets('signed out, nobody is you', (tester) async {
    await tester.pumpWidget(app(const HandleLink('me')));
    await tester.pump();

    expect(tester.widget<Text>(find.text('@me')).style!.color, Palette.dark.ink);
  });

  testWidgets('the time and the reply count are underlined apart', (tester) async {
    await tester.pumpWidget(
      app(PostMeta(createdAt: DateTime.now().subtract(const Duration(hours: 13)), replyCount: 2)),
    );
    await tester.pump();

    final parts = (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan)
        .children!
        .cast<TextSpan>();

    expect(parts.map((part) => part.text), ['13h', ' · ', '2 replies']);
    expect(parts[0].style!.decoration, TextDecoration.underline);
    expect(parts[1].style!.decoration ?? TextDecoration.none, TextDecoration.none);
    expect(parts[2].style!.decoration, TextDecoration.underline);
    expect(
      parts[0].style!.decorationThickness,
      parts[2].style!.decorationThickness,
      reason: 'both rules are drawn the same',
    );
  });

  testWidgets('a post with no replies is just a time', (tester) async {
    await tester.pumpWidget(app(PostMeta(createdAt: DateTime.now(), replyCount: 0)));
    await tester.pump();

    final parts = (tester.widget<Text>(find.byType(Text)).textSpan! as TextSpan).children!;
    expect(parts.length, 1);
  });
}
