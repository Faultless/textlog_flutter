import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/execution.dart';

void main() {
  group('what a #exec post shows', () {
    test('short output, unchanged', () {
      expect(displayedExecutionOutput('hello\nworld'), 'hello\nworld');
    });

    test('trailing blank lines go', () {
      expect(displayedExecutionOutput('hello\n\n\n'), 'hello');
    });

    test('carriage returns are lines like any other', () {
      expect(displayedExecutionOutput('a\r\nb\rc'), 'a\nb\nc');
    });

    test('a long run of lines keeps the beginning and the last one', () {
      // The last line is usually the answer; the middle is usually a loop.
      final total = executionLineLimit + 40;
      final output = [for (var i = 1; i <= total; i++) 'line $i'].join('\n');
      final shown = displayedExecutionOutput(output).split('\n');

      expect(shown, hasLength(executionLineLimit));
      expect(shown.first, 'line 1');
      expect(shown[executionLineLimit - 2], '…');
      expect(shown.last, 'line $total');
    });

    test('the middle is folded away, not thrown away', () {
      final total = executionLineLimit + 40;
      final output = [for (var i = 1; i <= total; i++) 'line $i'].join('\n');
      final parts = displayedExecutionOutputParts(output);

      expect(parts.hasOmission, isTrue);
      final omitted = parts.omitted.split('\n');
      // Everything between the head and the final line, and nothing else.
      expect(omitted.first, 'line ${executionLineLimit - 1}');
      expect(omitted.last, 'line ${total - 1}');
      expect(
        (executionLineLimit - 2) + omitted.length + 1,
        total,
        reason: 'head + middle + last line accounts for every line printed',
      );
    });

    test('a diagram the size mermaid actually draws is shown whole', () {
      // The real thing: post 3487 on textlog.cc is twenty-five lines. The old
      // ten-line cap took the bottom off it.
      final diagram = [for (var i = 1; i <= 25; i++) 'row $i'].join('\n');
      final parts = displayedExecutionOutputParts(diagram);

      expect(parts.hasOmission, isFalse);
      expect(parts.visible.split('\n'), hasLength(25));
    });

    test('a long line is cut, not wrapped', () {
      final shown = displayedExecutionOutput('x' * 500);
      expect(shown, hasLength(executionLineLength));
      expect(shown.endsWith('…'), isTrue);
    });

    test("the sandbox's own death rattle is not output", () {
      expect(
        displayedExecutionOutput('done\nSandbox keeper received fatal signal 6'),
        'done',
      );
    });

    test('nothing printed is nothing to draw', () {
      expect(hasExecutionOutput(null), isFalse);
      expect(hasExecutionOutput(''), isFalse);
      expect(hasExecutionOutput('   \n  '), isFalse);
      expect(hasExecutionOutput('0'), isTrue);
    });
  });
}
