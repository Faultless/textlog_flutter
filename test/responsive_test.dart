import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/ui/widgets/shell.dart';

/// Findings from driving the web build in a phone-sized viewport, pinned so they
/// cannot come back:
///
/// * every text link was a 16px-tall tap target (see barebones_test for the fix)
/// * five levels of reply nesting ate a quarter of a 390px screen
/// * a post body ran the full width of a 1280px window
/// * at 320px the appearance control was pushed off the right edge of the header
void main() {
  /// Give [child] exactly [width] of room and measure what it takes.
  ///
  /// A real width rather than a MediaQuery override: layout constraints come from
  /// the render tree, not from MediaQueryData, so overriding the latter measures
  /// the test surface instead of the widget.
  Future<Size> render(WidgetTester tester, double width, Widget child) async {
    await tester.pumpWidget(
      Directionality(
        textDirection: TextDirection.ltr,
        child: Center(
          child: SizedBox(width: width, height: 900, child: child),
        ),
      ),
    );
    return tester.getSize(find.byType(ColoredBox).first);
  }

  group('the reading column', () {
    testWidgets('holds a body to a measure on a wide window', (tester) async {
      final size = await render(
        tester,
        1280,
        const ReadingColumn(
          // Expand, so the box takes the width the column allows rather than zero.
          child: SizedBox.expand(child: ColoredBox(color: Color(0xff000000))),
        ),
      );
      // The site's own `header, main { max-width: 760px }`.
      expect(size.width, ReadingColumn.maxWidth);
    });

    testWidgets('gives a phone the whole screen', (tester) async {
      final size = await render(
        tester,
        390,
        const ReadingColumn(
          // Expand, so the box takes the width the column allows rather than zero.
          child: SizedBox.expand(child: ColoredBox(color: Color(0xff000000))),
        ),
      );
      expect(size.width, 390);
    });
  });
}
