import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:textlog/core/locks.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/reply_tree.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/reply_tree.dart';

Post post(int id, {List<String> tags = const [], Post? parent, int replies = 0}) => Post(
  id: id,
  body: 'post $id',
  createdAt: DateTime(2026, 8, 8),
  parentId: parent?.id,
  replyCount: replies,
  tags: tags,
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/$id'),
  author: Author(handle: 'a', url: Uri.parse('https://textlog.cc/u/a')),
  parent: parent,
);

ReplyNode node(int id, {List<String> tags = const [], List<ReplyNode> children = const []}) =>
    ReplyNode(post: post(id, tags: tags), children: children, unloaded: 0);

void main() {
  group('the lock rule', () {
    test('a #lock on the post closes it', () {
      expect(locksThread(post(1, tags: ['lock'])), isTrue);
      expect(locksThread(post(1, tags: ['tlog'])), isFalse);
      expect(locksThread(post(1, tags: ['LOCK'])), isTrue, reason: 'the tag is folded');
    });

    test('the inlined parent closes it too', () {
      final locked = post(1, tags: ['lock']);
      expect(threadLocked(post(2, parent: locked)), isTrue);
      expect(threadLocked(post(2, parent: post(1))), isFalse);
    });

    test('a tree can say what a post cannot see for itself', () {
      // Past the inlined parent the app has no ancestors, so the tree carries it.
      expect(threadLocked(post(9), inherited: true), isTrue);
    });
  });

  group('a locked thread', () {
    Future<void> show(WidgetTester tester, List<ReplyNode> nodes,
        {bool lockedAbove = false}) async {
      SharedPreferences.setMockInitialValues({});
      final router = GoRouter(routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => Scaffold(
            body: SingleChildScrollView(
              child: ReplyBranch(nodes, rootId: 1, lockedAbove: lockedAbove),
            ),
          ),
        ),
      ]);
      addTearDown(router.dispose);
      await tester.pumpWidget(ProviderScope(
        child: MaterialApp.router(theme: textlogTheme(Palette.dark), routerConfig: router),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('says so instead of offering a reply', (tester) async {
      await show(tester, [node(2)],
          lockedAbove: true);

      expect(find.text('thread locked'), findsOneWidget);
      expect(find.text('sign in to reply'), findsNothing);
    });

    testWidgets('an open thread still offers one', (tester) async {
      await show(tester, [node(2)]);

      expect(find.text('thread locked'), findsNothing);
      expect(find.text('sign in to reply'), findsOneWidget);
    });

    testWidgets('a lock partway down closes only what is under it', (tester) async {
      await show(tester, [
        node(2, children: [
          node(3, tags: ['lock'], children: [node(4)]),
        ]),
      ]);

      // 2 is above the lock and still open; 3 carries it and 4 sits under it.
      expect(find.text('sign in to reply'), findsOneWidget);
      expect(find.text('thread locked'), findsNWidgets(2));
    });
  });

  test('the server has the last word', () {
    const failure = ApiFailure(
      code: 'thread_locked',
      message: 'This thread is locked',
      status: 409,
    );
    expect(failure.isThreadLocked, isTrue);
    expect(failure.isUnauthorized, isFalse, reason: 'not a reason to sign anyone out');
    expect(failure.isTransient, isFalse, reason: 'trying again will not help');
  });
}
