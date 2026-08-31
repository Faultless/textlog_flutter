import 'dart:async';

/// Ids the reader has scrolled past, held for a moment so a fling costs one request
/// rather than one per post.
class ReadQueue<T> {
  ReadQueue(this._send, {this.delay = const Duration(milliseconds: 400)});

  /// Sends one batch. Chunking and swallowing failures are its business.
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

  /// Send what has piled up. Also called on dispose, or the last posts of a session
  /// would come back unread.
  void flush() {
    _timer?.cancel();
    _timer = null;
    if (_pending.isEmpty) return;
    final going = _pending.toList();
    _pending.clear();
    unawaited(_send(going).catchError((Object _) {}));
  }

  /// Drop what is pending, when "mark everything" supersedes it.
  void clear() {
    _timer?.cancel();
    _timer = null;
    _pending.clear();
  }
}
