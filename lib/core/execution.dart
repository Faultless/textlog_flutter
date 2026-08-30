/// How much of a `#exec` post's output is shown.
///
/// textlog runs the code fence under a `#exec` line once, when the post is written,
/// and stores whatever it printed. The API hands that back whole; deciding how much
/// of it to show is the client's job, and the site's rules are these — ten lines,
/// two hundred characters a line, and the sandbox's own noise dropped. Ported rather
/// than invented so a post looks the same here as it does on the web.
///
/// Pure, so the rules are a test rather than an argument with a device.
library;

/// Lines beyond this are elided, with the last one kept: the end of a program's
/// output is usually the answer, and dropping it to show more of the middle would
/// hide the point of running it.
const executionLineLimit = 10;

/// Long lines are cut rather than wrapped. A run of a thousand characters is data,
/// not prose, and wrapping it would push the post off the screen.
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

/// Whether there is anything worth drawing. An empty string is a program that
/// printed nothing, and a box with nothing in it says less than no box at all.
bool hasExecutionOutput(String? output) =>
    output != null && displayedExecutionOutput(output).trim().isNotEmpty;
