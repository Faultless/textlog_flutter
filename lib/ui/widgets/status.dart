import 'dart:async';

import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../theme.dart';
import 'form_parts.dart';

String messageFor(Object error) => switch (error) {
  ApiFailure(isNotFound: true) => 'Not found.',
  ApiFailure(isRateLimited: true, :final retryAfter?) =>
    'Too many requests. Try again in ${humanDuration(retryAfter)}.',
  ApiFailure(isRateLimited: true) => 'Too many requests. Try again in a moment.',
  ApiFailure(:final message) => message,
  _ => 'Could not reach textlog.',
};

/// Rounded up.
String humanDuration(Duration duration) {
  if (duration.inSeconds < 60) return '${duration.inSeconds.clamp(1, 59)} seconds';
  final minutes = (duration.inSeconds / 60).ceil();
  if (minutes < 60) return '$minutes ${minutes == 1 ? 'minute' : 'minutes'}';
  final hours = (minutes / 60).ceil();
  return '$hours ${hours == 1 ? 'hour' : 'hours'}';
}

/// A message where content would be, with an optional retry.
///
/// Stateful because of what a retry looks like from the reader's side. Riverpod keeps
/// the previous error while a provider rebuilds, so the error branch of the calling
/// screen renders again — the same words and the same button, with nothing to say a
/// request is in flight. Tapping retry was indistinguishable from tapping nothing,
/// and on a network that failed twice it stayed that way. So the wait is shown here,
/// once, rather than asked of every screen that has an error state.
///
/// [onRetry] should therefore return a future that completes when the refetch does —
/// `notifier.refresh()`, or `ref.refresh(provider.future)` — not a bare `invalidate`,
/// which returns before there is anything to wait for.
class StatusMessage extends StatefulWidget {
  const StatusMessage(this.message, {super.key, this.onRetry});

  final String message;
  final FutureOr<void> Function()? onRetry;

  @override
  State<StatusMessage> createState() => _StatusMessageState();
}

class _StatusMessageState extends State<StatusMessage> {
  var _busy = false;

  Future<void> _retry() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onRetry!();
    } catch (_) {
      // The provider records its own failure and this widget rebuilds with the new
      // message. Rethrowing here would only be an unhandled error in a tap handler.
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            widget.message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: palette.muted),
          ),
          if (widget.onRetry != null) ...[
            const SizedBox(height: space4),
            // Not a spinner in place of the button: that moves the thing you just
            // pressed out from under your finger. The label carries the state and
            // the button stops accepting taps instead.
            TextlogButton(
              _busy ? 'retrying…' : 'retry',
              onPressed: _busy ? null : _retry,
            ),
          ],
        ],
      ),
    );
  }
}

class Spinner extends StatelessWidget {
  const Spinner({super.key});

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.all(space6),
    child: Center(
      child: context.chrome.plain
          // A spinning arc is the most Material thing on the screen. In barebones
          // mode it says so in words instead.
          ? Text(
              'loading…',
              style: Theme.of(context).textTheme.bodySmall!.copyWith(
                color: context.palette.muted,
              ),
            )
          : SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: context.palette.muted,
              ),
            ),
    ),
  );
}
