/// Minimal server-sent-events parser: a stream of lines in, the `data:` payloads
/// of one named event out. Pure, so it is tested against a list of literal lines.
library;

/// What a transport reports upward. The connection itself is an event, because the
/// client has to reconcile what it missed each time the stream comes back.
sealed class FirehoseFrame {
  const FirehoseFrame();
}

final class FirehoseOpened extends FirehoseFrame {
  const FirehoseOpened();
}

final class FirehosePayload extends FirehoseFrame {
  const FirehosePayload(this.json);
  final String json;
}

Stream<String> sseDataOf(Stream<String> lines, String eventName) async* {
  String? event;
  final data = StringBuffer();

  await for (final line in lines) {
    if (line.isEmpty) {
      if (event == eventName && data.isNotEmpty) yield data.toString();
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue; // heartbeat

    final separator = line.indexOf(':');
    final field = separator == -1 ? line : line.substring(0, separator);
    var value = separator == -1 ? '' : line.substring(separator + 1);
    if (value.startsWith(' ')) value = value.substring(1);

    if (field == 'event') {
      event = value;
    } else if (field == 'data') {
      if (data.isNotEmpty) data.write('\n');
      data.write(value);
    }
  }
}

/// The server answered the firehose with something other than a stream. Carries the
/// status so the reconnect loop can tell "slow down" from "try again".
final class FirehoseRefused implements Exception {
  const FirehoseRefused(this.status, {this.retryAfter});

  final int status;
  final Duration? retryAfter;

  bool get isRateLimited => status == 429;

  @override
  String toString() => 'firehose refused ($status)';
}
