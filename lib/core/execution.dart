/// How much of a `#exec` or `#mermaid` post's output is shown. The API returns it
/// whole; these are the site's display rules, ported so a post looks the same in both.
///
/// `#mermaid` is the same machinery seen from the other end: the server renders the
/// diagram to ASCII with `mermaid-ascii` and stores it in the very same
/// `execution_output` field, so a diagram arrives here already drawn and this file
/// needs to know nothing about mermaid beyond leaving it room.
library;

/// Lines beyond this move into [ExecutionOutputParts.omitted] rather than being lost.
///
/// A hundred, which is the server's own figure. It was ten here, from a much earlier
/// reading of the site, and that was wrong in a way mermaid made obvious: a modest
/// diagram runs to twenty-five lines, so the app was cutting the bottom off drawings
/// the website shows whole.
const executionLineLimit = 100;

/// Long lines are cut, not wrapped.
const executionLineLength = 200;

/// The sandbox says this to itself when it is killed. It is not output.
const _fatalSignal = 'Sandbox keeper received fatal signal 6';

/// Output split the way the site splits it: what is shown, and what waits behind the
/// `…` in the middle of it.
///
/// The elision is not a truncation. The site keeps the first lines and the last one —
/// usually the answer — and folds everything between them into a `<details>` the
/// reader can open, so nothing a program printed is actually thrown away.
final class ExecutionOutputParts {
  const ExecutionOutputParts(this.visible, this.omitted);

  /// Includes the `…` line, second from the end, when there is anything omitted.
  final String visible;

  /// The middle, empty when it all fitted.
  final String omitted;

  bool get hasOmission => omitted.isNotEmpty;
}

ExecutionOutputParts displayedExecutionOutputParts(String output) {
  final normalised = output
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((line) => !line.contains(_fatalSignal))
      .join('\n')
      .trimRight();

  String bounded(String line) => line.length <= executionLineLength
      ? line
      : '${line.substring(0, executionLineLength - 1)}…';

  final lines = [for (final line in normalised.split('\n')) bounded(line)];
  if (lines.length <= executionLineLimit) {
    return ExecutionOutputParts(lines.join('\n'), '');
  }

  final kept = executionLineLimit - 2;
  return ExecutionOutputParts(
    [...lines.take(kept), '…', lines.last].join('\n'),
    lines.sublist(kept, lines.length - 1).join('\n'),
  );
}

/// [output] as it should appear under the post, the omitted middle left folded.
String displayedExecutionOutput(String output) =>
    displayedExecutionOutputParts(output).visible;

/// Whether there is anything worth drawing — an empty string is a program that
/// printed nothing.
bool hasExecutionOutput(String? output) =>
    output != null && displayedExecutionOutput(output).trim().isNotEmpty;
