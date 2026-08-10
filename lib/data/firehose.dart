import 'dart:convert';

import '../core/models.dart';
import '../core/sse.dart';
import 'api.dart';
import 'sse_io.dart' if (dart.library.js_interop) 'sse_web.dart';

/// textlog.cc closes the firehose after about twelve seconds. Its own keep-alive
/// heartbeat is on a fifteen-second timer, so it never fires in time — something in
/// front of the app (it answers `via: 1.1 Caddy`) drops the idle connection first.
///
/// That is a server-side problem and cannot be fixed from here, so the client is
/// built to expect it: a close is normal, reconnect quickly, and reconcile whatever
/// was missed. Backing off exponentially would be exactly wrong — the earlier version
/// treated a twelve-second session as unhealthy and drifted out to a 30s retry, which
/// missed far more than it caught.
const _reconnectDelay = Duration(seconds: 1);

/// Real failures — refused, rate limited, offline — still back off.
const _minBackoff = Duration(seconds: 2);
const _maxBackoff = Duration(seconds: 30);

/// Ceiling on an obeyed `Retry-After`, so the live tab always comes back.
const _maxWait = Duration(minutes: 2);

sealed class FirehoseEvent {
  const FirehoseEvent();
}

/// The stream is live. Anything published while it was down was missed, so this is
/// the cue to reconcile.
final class FirehoseConnected extends FirehoseEvent {
  const FirehoseConnected();
}

final class FirehosePost extends FirehoseEvent {
  const FirehosePost(this.post);
  final Post post;
}

Stream<FirehoseEvent> firehose() async* {
  var backoff = _minBackoff;

  while (true) {
    var connected = false;
    Duration? askedToWait;
    try {
      await for (final frame in connectFirehose(apiBase.resolve('firehose'))) {
        switch (frame) {
          case FirehoseOpened():
            connected = true;
            backoff = _minBackoff;
            yield const FirehoseConnected();
          case FirehosePayload(:final json):
            yield FirehosePost(Post.fromJson(jsonDecode(json) as Map<String, dynamic>));
        }
      }
    } on FirehoseRefused catch (refused) {
      // A limit is the one refusal that says how long.
      if (refused.isRateLimited) askedToWait = refused.retryAfter ?? _maxBackoff;
    } catch (_) {
      // Fall through: a dropped stream is expected here, not fatal.
    }

    if (askedToWait != null) {
      await Future<void>.delayed(askedToWait > _maxWait ? _maxWait : askedToWait);
      backoff = _minBackoff;
    } else if (connected) {
      await Future<void>.delayed(_reconnectDelay);
    } else {
      await Future<void>.delayed(backoff);
      backoff = backoff * 2 > _maxBackoff ? _maxBackoff : backoff * 2;
    }
  }
}
