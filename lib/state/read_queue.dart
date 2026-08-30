import 'dart:async';

/// Ids the reader has scrolled past, held for a moment so a fling is one request.
///
/// Reading now marks a post the instant it comes into view rather than when the
/// scroll stops, which is the behaviour a reader expects and also several marks a
/// second while a thumb is moving. On screen that is free — the notifier is
/// optimistic, so the rail goes immediately — but one request per post would be
/// absurd, so the ids pile up here and go out together once the reader pauses.
class ReadQueue<T> {
  ReadQueue(this._send, {this.delay = const Duration(milliseconds: 400)});

  /// Sends one batch. Chunking to whatever the endpoint accepts is its business,
  /// as is swallowing a failure: by then the reader has moved on.
  final Future<void> Function(List<T> ids) _send;

  final Duration delay;

  final _pending = <T>{};
  Timer? _timer;

  void add(Iterable<T> ids) {
    _pending.addAll(ids);
    if (_pending.isEmpty) return;
    _timer?.cancel();
    _timer = Timer(delay, flush);
  }

  /// Send what has piled up, now. Called on the timer, and again when the feed is
  /// disposed — leaving the last few posts of a session unsent would mean their
  /// rails came back next launch, which is exactly the complaint.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final going = _pending.toList();
    _pending.clear();
    unawaited(_send(going).catchError((Object _) {}));
  }

  /// Drop what is pending, for when a "mark everything" request supersedes it.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
