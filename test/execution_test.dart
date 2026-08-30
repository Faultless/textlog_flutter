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
      final output = [for (var i = 1; i <= 40; i++) 'line $i'].join('\n');
      final shown = displayedExecutionOutput(output).split('\n');

      expect(shown, hasLength(executionLineLimit));
      expect(shown.first, 'line 1');
      expect(shown[executionLineLimit - 2], '…');
      expect(shown.last, 'line 40');
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
