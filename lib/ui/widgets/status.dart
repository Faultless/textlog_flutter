import 'package:flutter/material.dart';

import '../../core/models.dart';
import '../theme.dart';

String messageFor(Object error) => switch (error) {
  ApiFailure(isNotFound: true) => 'Not found.',
  ApiFailure(isRateLimited: true) => 'Rate limited — try again in a moment.',
  ApiFailure(:final message) => message,
  _ => 'Could not reach textlog.',
};

class StatusMessage extends StatelessWidget {
  const StatusMessage(this.message, {super.key, this.onRetry});

  final String message;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space6),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall!.copyWith(color: palette.muted),
          ),
          if (onRetry != null) ...[
            const SizedBox(height: space4),
            TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: palette.accent),
              child: Text('retry', style: Theme.of(context).textTheme.bodySmall),
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
      child: SizedBox(
        width: 16,
        height: 16,
        child: CircularProgressIndicator(strokeWidth: 1.5, color: context.palette.muted),
      ),
    ),
  );
}
