import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/sse.dart';
import 'api.dart';

/// Mobile/desktop transport: a long-lived streamed GET, split into lines.
Stream<FirehoseFrame> connectFirehose(Uri url) async* {
  final client = http.Client();
  try {
    final request = http.Request('GET', url)..headers['accept'] = 'text/event-stream';
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw FirehoseRefused(response.statusCode, retryAfter: retryAfterOf(response.headers));
    }

    yield const FirehoseOpened();

    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    yield* sseDataOf(lines, 'post').map(FirehosePayload.new);
  } finally {
    client.close();
  }
}
