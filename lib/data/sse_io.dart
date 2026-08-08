import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/sse.dart';

/// Mobile/desktop transport: a long-lived streamed GET, split into lines.
Stream<String> connectPostEvents(Uri url) async* {
  final client = http.Client();
  try {
    final request = http.Request('GET', url)..headers['accept'] = 'text/event-stream';
    final response = await client.send(request);
    if (response.statusCode != 200) {
      throw http.ClientException('firehose refused (${response.statusCode})', url);
    }
    final lines = response.stream.transform(utf8.decoder).transform(const LineSplitter());
    yield* sseDataOf(lines, 'post');
  } finally {
    client.close();
  }
}
