import 'dart:convert';

import '../core/models.dart';
import 'api.dart';
import 'sse_io.dart' if (dart.library.js_interop) 'sse_web.dart';

const _minBackoff = Duration(seconds: 1);
const _maxBackoff = Duration(seconds: 30);

/// A session this long is evidence the server is healthy, so the next retry starts
/// from the shortest delay instead of inheriting the previous backoff.
const _healthySession = Duration(seconds: 30);

/// Every new post on textlog, as it happens. Reconnects with exponential backoff —
/// the server drops idle streams and allows only three per IP.
Stream<Post> firehose() async* {
  var backoff = _minBackoff;

  while (true) {
    final startedAt = DateTime.now();
    try {
      await for (final data in connectPostEvents(apiBase.resolve('firehose'))) {
        yield Post.fromJson(jsonDecode(data) as Map<String, dynamic>);
      }
    } catch (_) {
      // Fall through to the backoff below; a dropped stream is expected, not fatal.
    }
    if (DateTime.now().difference(startedAt) > _healthySession) backoff = _minBackoff;
    await Future<void>.delayed(backoff);
    backoff = backoff * 2 > _maxBackoff ? _maxBackoff : backoff * 2;
  }
}
