import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

import '../core/sse.dart';

/// `EventSource.CLOSED` — the only terminal readyState.
const _closed = 2;

/// Web transport: `package:http` buffers the whole body in the browser, so the
/// native EventSource is the only way to get incremental delivery here.
Stream<FirehoseFrame> connectFirehose(Uri url) {
  web.EventSource? source;
  late final StreamController<FirehoseFrame> controller;

  controller = StreamController<FirehoseFrame>(
    onListen: () {
      final opened = web.EventSource(url.toString());
      source = opened;

      opened.addEventListener(
        'open',
        (web.Event _) {
          controller.add(const FirehoseOpened());
        }.toJS,
      );
      opened.addEventListener(
        'post',
        (web.Event event) {
          final data = (event as web.MessageEvent).data.dartify();
          if (data is String) controller.add(FirehosePayload(data));
        }.toJS,
      );
      opened.addEventListener(
        'error',
        (web.Event _) {
          // EventSource reconnects by itself, and fires 'error' on every transient
          // drop. Surfacing those would stack our own retry loop on top of the
          // browser's and blow through the server's three-streams-per-IP limit.
          if (opened.readyState == _closed) {
            controller.addError(StateError('firehose closed'));
          }
        }.toJS,
      );
    },
    onCancel: () => source?.close(),
  );

  return controller.stream;
}
