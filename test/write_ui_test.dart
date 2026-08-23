import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/session.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/ui/screens/me.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/compose_sheet.dart';
import 'package:textlog/ui/widgets/post_actions.dart';

Map<String, dynamic> postJson(int id, String handle, {String body = 'hello'}) => {
  'id': id,
  'body': body,
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': null,
  'reply_count': 0,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'api_url': 'https://textlog.cc/api/v1/posts/$id',
  'author': {
    'handle': handle,
    'url': 'https://textlog.cc/u/$handle',
    'api_url': 'https://textlog.cc/api/v1/users/$handle',
  },
};

Post samplePost({int id = 1, String handle = 'me', String body = 'hello'}) =>
    Post.fromJson(postJson(id, handle, body: body));

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

/// Records what the app asked the server for, and answers with [reply].
({http.Client client, List<String> calls}) recorder([
  http.Response Function(http.BaseRequest)? reply,
]) {
  final calls = <String>[];
  final client = MockClient((request) async {
    calls.add('${request.method} ${request.url.path}');
    return reply?.call(request) ?? http.Response('', 204);
  });
  return (client: client, calls: calls);
}

/// The key matters: pumping a second tree in one test has to build a new scope,
/// or the session override from the first one is what the widgets keep reading.
Widget app(Widget child, {Session? session, http.Client? client, bool bare = false}) => ProviderScope(
  key: UniqueKey(),
  overrides: [
    sessionProvider.overrideWith(() => FakeSession(session)),
    if (client != null) httpClientProvider.overrideWithValue(client),
  ],
  child: MaterialApp(
    theme: textlogTheme(Palette.dark),
    // Screens bring their own Scaffold; loose widgets need one for sheets and toasts.
    home: bare ? child : Scaffold(body: child),
  ),
);

/// Enough frames for a sheet or dialog to finish opening. A focused text field
/// keeps blinking forever, so pumpAndSettle is not an option here.
Future<void> settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 350));
  await tester.pump(const Duration(milliseconds: 350));
}

/// Opens the actions overflow, where everything but reply now lives.
Future<void> openMenu(WidgetTester tester) async {
  await tester.tap(find.byIcon(Icons.more_horiz));
  await settle(tester);
}

/// A button that opens the sheet under test, so the sheet gets a real route.
Widget opens(Future<void> Function(BuildContext) open) => Builder(
  builder: (context) => TextButton(onPressed: () => open(context), child: const Text('open')),
);

void main() {
  testWidgets('the actions offered depend on who is looking', (tester) async {
    Future<void> show(Session? session, Post post) async {
      await tester.pumpWidget(
        app(
          Consumer(builder: (context, ref, _) => Row(children: postActions(context, ref, post))),
          session: session,
        ),
      );
      await settle(tester);
    }

    // Signed out there is nothing to put in a menu, so there is no menu — and the
    // action says what it will actually do, as the site's `enter to reply` does.
    await show(null, samplePost(handle: 'someone'));
    expect(find.text('sign in to reply'), findsOneWidget);
    expect(find.byIcon(Icons.more_horiz), findsNothing);

    await show(signedIn, samplePost(handle: 'someone'));
    expect(find.text('reply'), findsOneWidget);
    expect(find.text('report'), findsNothing, reason: 'not until the menu is opened');
    await openMenu(tester);
    expect(find.text('report'), findsOneWidget);
    expect(find.text('edit'), findsNothing);

    await show(signedIn, samplePost(handle: 'me'));
    // Replying to yourself is a continuation, and the site words it that way.
    expect(find.text('continue'), findsOneWidget);
    await openMenu(tester);
    expect(find.text('edit'), findsOneWidget);
    expect(find.text('delete'), findsOneWidget);
    expect(find.text('report'), findsNothing);
  });

  testWidgets('editing opens with the post in it and saves the change', (tester) async {
    final http = recorder(
      (request) => jsonResponse(jsonEncode({'data': postJson(1, 'me', body: 'a better hello')})),
    );
    await tester.pumpWidget(
      app(
        opens(
          (context) => showCompose(context, kind: ComposeKind.edit, target: samplePost(body: 'hello')),
        ),
        session: signedIn,
        client: http.client,
      ),
    );
    await settle(tester);

    await tester.tap(find.text('open'));
    await settle(tester);
    expect(find.text('hello'), findsOneWidget);
    expect(find.textContaining('Edit your post'), findsOneWidget);

    await tester.enterText(find.byType(TextField), 'a better hello');
    await tester.pump();
    await tester.tap(find.text('save →'));
    await settle(tester);

    expect(http.calls, ['PATCH /api/v1/posts/1']);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('the keyboard does not cover what you are typing into', (tester) async {
    addTearDown(tester.view.reset);
    final ratio = tester.view.devicePixelRatio;
    final screen = tester.view.physicalSize.height / ratio;
    const keyboard = 300.0;

    await tester.pumpWidget(
      app(opens((context) => showCompose(context)), session: signedIn, client: recorder().client),
    );
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);

    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * ratio);
    await settle(tester);

    // Reading the insets from the calling context instead of the sheet's used to
    // leave the field sitting behind the keyboard.
    expect(tester.getBottomLeft(find.byType(TextField)).dy, lessThanOrEqualTo(screen - keyboard));
    expect(tester.getBottomLeft(find.text('post →')).dy, lessThanOrEqualTo(screen - keyboard));
    expect(tester.takeException(), isNull);
  });

  testWidgets('the keyboard does not cover the sign in field either', (tester) async {
    SharedPreferences.setMockInitialValues({});
    addTearDown(tester.view.reset);
    final ratio = tester.view.devicePixelRatio;
    final screen = tester.view.physicalSize.height / ratio;
    const keyboard = 300.0;

    await tester.pumpWidget(app(const MeScreen(), bare: true));
    await settle(tester);
    expect(find.text('send code →'), findsOneWidget);

    tester.view.viewInsets = FakeViewPadding(bottom: keyboard * ratio);
    await settle(tester);

    expect(tester.getBottomLeft(find.byType(TextField)).dy, lessThanOrEqualTo(screen - keyboard));
    expect(tester.takeException(), isNull);
  });

  testWidgets('an empty post is refused before it reaches the server', (tester) async {
    final http = recorder();
    await tester.pumpWidget(
      app(
        opens((context) => showCompose(context)),
        session: signedIn,
        client: http.client,
      ),
    );
    await settle(tester);

    await tester.tap(find.text('open'));
    await settle(tester);
    await tester.tap(find.text('post →'));
    await settle(tester);

    expect(http.calls, isEmpty);
    expect(find.textContaining('between 1 and 280'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
  });

  testWidgets('deleting asks first, and cancelling changes nothing', (tester) async {
    final http = recorder();
    await tester.pumpWidget(
      app(
        Consumer(
          builder: (context, ref, _) => Row(children: postActions(context, ref, samplePost())),
        ),
        session: signedIn,
        client: http.client,
      ),
    );
    await settle(tester);

    await openMenu(tester);
    await tester.tap(find.text('delete'));
    await settle(tester);
    expect(find.text('Delete this post'), findsOneWidget);

    await tester.tap(find.text('cancel'));
    await settle(tester);
    expect(http.calls, isEmpty);

    await openMenu(tester);
    await tester.tap(find.text('delete'));
    await settle(tester);
    await tester.tap(find.widgetWithText(TextButton, 'delete'));
    await settle(tester);
    expect(http.calls, ['DELETE /api/v1/posts/1']);
  });

  testWidgets('reporting collects a reason and sends it', (tester) async {
    final http = recorder();
    await tester.pumpWidget(
      app(
        Consumer(
          builder: (context, ref, _) =>
              Row(children: postActions(context, ref, samplePost(handle: 'someone'))),
        ),
        session: signedIn,
        client: http.client,
      ),
    );
    await settle(tester);

    await openMenu(tester);
    await tester.tap(find.text('report'));
    await settle(tester);
    expect(find.text('report @someone'), findsOneWidget);

    // Every reason the server accepts is offered, and the sheet fits them all —
    // a fifth one used to overflow it.
    for (final reason in ['harassment', 'spam', 'impersonation', 'bot', 'other']) {
      expect(find.text(reason), findsOneWidget, reason: reason);
    }
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('bot'));
    await settle(tester);
    expect(http.calls, ['POST /api/v1/posts/1/report']);
    expect(find.textContaining('Thank you'), findsOneWidget);
  });

  testWidgets('following is offered to other people only, and toggles', (tester) async {
    final http = recorder();
    Future<void> show(Session? session, String handle) async {
      await tester.pumpWidget(app(FollowButton(handle), session: session, client: http.client));
      await settle(tester);
    }

    await show(null, 'someone');
    expect(find.text('follow'), findsNothing);

    await show(signedIn, 'me');
    expect(find.text('follow'), findsNothing);

    // The API puts no follow state on a profile, so until our own following list
    // answers the button holds back its arrow rather than claiming to know.
    await show(signedIn, 'someone');
    expect(find.text('follow'), findsOneWidget);

    await tester.tap(find.text('follow'));
    await settle(tester);
    expect(find.text('unfollow'), findsOneWidget);

    await tester.tap(find.text('unfollow'));
    await settle(tester);
    // Now it is known: we just unfollowed, whatever the list walk managed.
    expect(find.text('follow →'), findsOneWidget);
    expect(
      http.calls.where((call) => call.endsWith('/follow')),
      ['POST /api/v1/users/someone/follow', 'DELETE /api/v1/users/someone/follow'],
    );
  });
}

/// A JSON body with the headers the client expects.
http.Response jsonResponse(String body, [int status = 200]) =>
    http.Response(body, status, headers: {'content-type': 'application/json'});
