/// How much of a `#exec` post's output is shown. The API returns it whole; these are
/// the site's display rules, ported so a post looks the same in both.
library;

/// Lines beyond this are elided, keeping the last one — usually the answer.
const executionLineLimit = 10;

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
