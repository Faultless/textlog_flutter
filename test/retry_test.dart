import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/ui/screens/profile.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/feed_view.dart';

const utf8Json = {'content-type': 'application/json; charset=utf-8'};

/// A server whose next answer is held until the test says so.
class Held {
  Completer<http.Response>? pending;
  var calls = 0;

  Future<http.Response> handle(http.BaseRequest _) {
    calls++;
    return (pending = Completer<http.Response>()).future;
  }

  void fail() => pending!.complete(http.Response('nope', 500));
  void succeed(String body) =>
      pending!.complete(http.Response(body, 200, headers: utf8Json));
}

Future<Held> show(WidgetTester tester, Widget screen) async {
  SharedPreferences.setMockInitialValues({});
  final held = Held();
  final router = GoRouter(
    initialLocation: '/x',
    routes: [GoRoute(path: '/x', builder: (_, _) => screen)],
  );
  addTearDown(router.dispose);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [httpClientProvider.overrideWithValue(MockClient(held.handle))],
      child: MaterialApp.router(theme: textlogTheme(Palette.dark), routerConfig: router),
    ),
  );
  await tester.pump();
  return held;
}

void main() {
  group('retry', () {
    testWidgets('says it is retrying while the request is in flight', (tester) async {
      // The whole bug: Riverpod keeps the old error while the provider rebuilds, so
      // the error branch drew the same words and the same button. Tapping retry was
      // indistinguishable from tapping nothing, and people pulled down instead.
      final held = await show(tester, const Scaffold(body: FeedView(LatestFeed())));
      held.fail();
      await tester.pumpAndSettle();
      expect(find.text('retry'), findsOneWidget);

      await tester.tap(find.text('retry'));
      await tester.pump();

      expect(find.text('retrying…'), findsOneWidget, reason: 'something is happening');
      expect(find.text('retry'), findsNothing);
      expect(held.calls, 2);

      held.fail();
      await tester.pumpAndSettle();
    });

    testWidgets('goes back to offering a retry when it fails again', (tester) async {
      final held = await show(tester, const Scaffold(body: FeedView(LatestFeed())));
      held.fail();
      await tester.pumpAndSettle();

      await tester.tap(find.text('retry'));
      await tester.pump();
      held.fail();
      await tester.pumpAndSettle();

      expect(find.text('retry'), findsOneWidget);
      expect(find.text('retrying…'), findsNothing);
    });

    testWidgets('a second tap while waiting does not fire another request',
        (tester) async {
      final held = await show(tester, const Scaffold(body: FeedView(LatestFeed())));
      held.fail();
      await tester.pumpAndSettle();

      await tester.tap(find.text('retry'));
      await tester.pump();
      await tester.tap(find.text('retrying…'));
      await tester.pump();

      expect(held.calls, 2, reason: 'the button stops accepting taps while it waits');
      held.fail();
      await tester.pumpAndSettle();
    });

    testWidgets('the content replaces the message when it works', (tester) async {
      final held = await show(tester, const Scaffold(body: FeedView(LatestFeed())));
      held.fail();
      await tester.pumpAndSettle();

      await tester.tap(find.text('retry'));
      await tester.pump();
      held.succeed('{"data":[],"pagination":{"next_cursor":null}}');
      await tester.pumpAndSettle();

      expect(find.text('retry'), findsNothing);
      expect(find.text('retrying…'), findsNothing);
      expect(find.text('Nothing here yet.'), findsOneWidget);
    });

    testWidgets('a failed profile offers one at all', (tester) async {
      // It used to be the one screen that stated the problem and left it there.
      final held = await show(tester, const ProfileScreen(handle: 'alice'));
      held.fail();
      await tester.pumpAndSettle();

      expect(find.text('retry'), findsWidgets);
      await tester.tap(find.text('retry').first);
      await tester.pump();
      expect(held.calls, greaterThan(1));
      held.fail();
      await tester.pumpAndSettle();
    });
  });
}
