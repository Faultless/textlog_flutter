import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/ui/theme.dart';
import 'package:textlog/ui/widgets/post_meta.dart';

Post reply({
  String handle = 'a_very_long_handle_here',
  String parentHandle = 'another_long_handle_xy',
}) => Post(
  id: 2,
  body: 'hello',
  createdAt: DateTime(2026, 8, 8),
  parentId: 1,
  replyCount: 24,
  tags: const [],
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/2'),
  author: Author(handle: handle, url: Uri.parse('https://textlog.cc/u/$handle')),
  parent: Post(
    id: 1,
    body: 'parent',
    createdAt: DateTime(2026, 8, 8),
    parentId: null,
    replyCount: 24,
    tags: const [],
    mentions: const [],
    url: Uri.parse('https://textlog.cc/post/1'),
    author: Author(
      handle: parentHandle,
      url: Uri.parse('https://textlog.cc/u/$parentHandle'),
    ),
  ),
);

/// A fold control, standing in for the real one.
const _fold = SizedBox(width: 24, height: 22, key: Key('fold'));

Future<Size> show(
  WidgetTester tester, {
  required double width,
  required bool singleLine,
  bool withControl = true,
}) async {
  await tester.pumpWidget(
    ProviderScope(
      child: MaterialApp(
        theme: textlogTheme(Palette.dark),
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: SizedBox(
              width: width,
              child: PostContextLine(
                post: reply(),
                singleLine: singleLine,
                showReplyCount: false,
                trailing: withControl ? const [_fold] : const [],
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pump();
  return tester.getSize(find.byType(PostContextLine));
}

void main() {
  group('the accordion header', () {
    testWidgets('stays on one line at phone widths', (tester) async {
      // Two twenty-odd-character handles and a stamp will not fit across 320px.
      // Wrapping put the fold control on a second row, which reads as broken.
      final single = await show(tester, width: 320, singleLine: true);
      final wrapped = await show(tester, width: 320, singleLine: false);

      expect(single.height, lessThan(wrapped.height));
      expect(tester.takeException(), isNull, reason: 'and it must not overflow');
    });

    testWidgets('keeps the control on the line', (tester) async {
      await show(tester, width: 320, singleLine: true);
      final line = tester.getRect(find.byType(PostContextLine));
      final fold = tester.getRect(find.byKey(const Key('fold')));

      expect(fold.right, lessThanOrEqualTo(line.right + 0.5));
      // Vertically inside the row rather than pushed below it.
      expect(fold.center.dy, closeTo(line.center.dy, line.height / 2));
    });

    testWidgets('abbreviates the handle rather than the stamp', (tester) async {
      await show(tester, width: 320, singleLine: true);

      // The stamp is the affordance that opens the post, so it keeps its room.
      final squeezedStamp = tester.getSize(find.byType(PostMeta));
      final squeezedHandle = tester.getSize(find.text('@a_very_long_handle_here'));

      await show(tester, width: 900, singleLine: true);
      final roomyStamp = tester.getSize(find.byType(PostMeta));
      final roomyHandle = tester.getSize(find.text('@a_very_long_handle_here'));

      expect(squeezedStamp.width, roomyStamp.width, reason: 'the stamp never gives way');
      expect(
        squeezedHandle.width,
        lessThan(roomyHandle.width),
        reason: 'the handle does, which is what the ellipsis is for',
      );
      expect(
        tester.widgetList<Text>(find.byType(Text)).any(
          (text) => text.overflow == TextOverflow.ellipsis,
        ),
        isTrue,
      );
    });

    testWidgets('says the whole thing when there is room', (tester) async {
      await show(tester, width: 900, singleLine: true);
      expect(find.text('@a_very_long_handle_here'), findsOneWidget);
      expect(find.text('@another_long_handle_xy'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('never overflows, at any width', (tester) async {
      for (final width in [240.0, 280.0, 320.0, 390.0, 500.0, 760.0]) {
        await show(tester, width: width, singleLine: true);
        expect(tester.takeException(), isNull, reason: 'at $width');
        expect(
          tester.getSize(find.byType(PostContextLine)).width,
          lessThanOrEqualTo(width),
          reason: 'at $width',
        );
      }
    });
  });

  testWidgets('a tile with no control on the line may still wrap', (tester) async {
    // Nothing there has to stay put, so showing everything beats abbreviating it.
    final size = await show(tester, width: 320, singleLine: false, withControl: false);
    expect(size.height, greaterThan(0));
    expect(tester.takeException(), isNull);
  });
}
