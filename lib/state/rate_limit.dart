import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Remembers that the server said 429, so the app stops adding requests to a limit
/// it has already tripped.
///
/// Only *background* traffic checks this: revalidating a thread you are reading,
/// reconnecting the firehose, paging a feed you scrolled to the end of. Anything
/// you actually asked for still goes to the server, because someone tapping retry
/// deserves a real answer rather than a guess from a stale timestamp.
final class RateLimitGate {
  /// A long `Retry-After` on one endpoint should not freeze reading everywhere for
  /// an hour: the auth limits are counted separately from the read limits, so a
  /// tripped sign-in says nothing about whether feeds are still allowed.
  static const _maxHold = Duration(minutes: 2);
  static const _fallback = Duration(seconds: 30);

  DateTime? _until;

  void trip(DateTime now, Duration? retryAfter) {
    final wait = retryAfter ?? _fallback;
    final until = now.add(wait > _maxHold ? _maxHold : wait);
    if (_until == null || until.isAfter(_until!)) _until = until;
  }

  /// A request that got through means whatever tripped us has passed.
  void clear() => _until = null;

  bool isTripped(DateTime now) => _until != null && now.isBefore(_until!);

  Duration? remaining(DateTime now) {
    final until = _until;
    if (until == null || !now.isBefore(until)) return null;
    return until.difference(now);
  }
}

final rateLimitProvider = Provider<RateLimitGate>((ref) => RateLimitGate());
