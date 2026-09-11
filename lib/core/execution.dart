/// How much of a `#exec` or `#mermaid` post's output is shown. The API returns it
/// whole; these are the site's display rules, ported so a post looks the same in both.
///
/// `#mermaid` is the same machinery seen from the other end: the server renders the
/// diagram to ASCII with `mermaid-ascii` and stores it in the very same
/// `execution_output` field, so a diagram arrives here already drawn and this file
/// needs to know nothing about mermaid beyond leaving it room.
library;

/// Lines beyond this are elided, keeping the last one — usually the answer.
///
/// Fifteen because that is what the server allows, raised from ten when mermaid
/// landed: a diagram is a good deal taller than a program's answer, and cutting one
/// at ten lines takes the bottom off the drawing.
const executionLineLimit = 15;

/// Long lines are cut, not wrapped.
const executionLineLength = 200;

/// The sandbox says this to itself when it is killed. It is not output.
const _fatalSignal = 'Sandbox keeper received fatal signal 6';

/// [output] as it should appear under the post.
String displayedExecutionOutput(String output) {
  final normalised = output
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n')
      .split('\n')
      .where((line) => !line.contains(_fatalSignal))
      .join('\n')
      .trimRight();

  final lines = normalised.split('\n');
  final limited = lines.length > executionLineLimit
      ? [...lines.take(executionLineLimit - 2), '…', lines.last]
      : lines;

  return [
    for (final line in limited)
      if (line.length <= executionLineLength)
        line
      else
        '${line.substring(0, executionLineLength - 1)}…',
  ].join('\n');
}

/// Whether there is anything worth drawing — an empty string is a program that
/// printed nothing.
bool hasExecutionOutput(String? output) =>
    output != null && displayedExecutionOutput(output).trim().isNotEmpty;
