import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../state/identity.dart';
import '../../state/session.dart';
import '../theme.dart';
import '../widgets/form_parts.dart';
import '../widgets/status.dart';
import 'web_action.dart';

/// The site's `/enter` flow: give an address, then type the code it emails you.
///
/// A server without the write endpoints answers 404 here, so the card falls back to
/// asking for a handle and the app keeps handing writes to the browser.
class SignInCard extends ConsumerStatefulWidget {
  const SignInCard({super.key});

  @override
  ConsumerState<SignInCard> createState() => _SignInCardState();
}

class _SignInCardState extends ConsumerState<SignInCard> {
  final _email = TextEditingController();
  final _code = TextEditingController();
  final _handle = TextEditingController();

  var _sent = false;
  var _busy = false;
  var _writesUnsupported = false;
  String? _error;

  @override
  void dispose() {
    _email.dispose();
    _code.dispose();
    _handle.dispose();
    super.dispose();
  }

  Future<void> _guard(Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await action();
    } on ApiFailure catch (failure) {
      if (!mounted) return;
      setState(() {
        // A limit has to say how long, or all you can do is keep tapping.
        _error = failure.isRateLimited ? messageFor(failure) : failure.message;
        // This server only serves reads.
        if (failure.isNotFound) _writesUnsupported = true;
      });
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach textlog.');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _requestCode() => _guard(() async {
    await ref.read(sessionProvider.notifier).requestCode(_email.text.trim());
    if (mounted) setState(() => _sent = true);
  });

  Future<void> _verify() =>
      _guard(() => ref.read(sessionProvider.notifier).verify(_email.text.trim(), _code.text.trim()));

  Future<void> _useHandle() async {
    final handle = _handle.text.trim().replaceFirst('@', '');
    if (!handlePattern.hasMatch(handle)) {
      setState(() => _error = 'Handles are 2–24 letters, numbers or underscores.');
      return;
    }
    await _guard(() => ref.read(identityProvider.notifier).remember(handle));
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('enter', style: theme.titleLarge),
          const SizedBox(height: space3),
          Text(
            _sent
                ? 'We sent a code to ${_email.text.trim()}. It expires in an hour.'
                : 'Sign in with your email. textlog sends a code, no password.',
            style: theme.bodyMedium!.copyWith(color: palette.quoteInk),
          ),
          const SizedBox(height: space5),
          FormMessage(_error),

          if (!_sent) ...[
            const FieldLabel('email'),
            TextlogField(
              controller: _email,
              hint: 'you@example.com',
              keyboardType: TextInputType.emailAddress,
              onSubmitted: (_) => _requestCode(),
            ),
            const SizedBox(height: space4),
            Row(
              children: [
                if (_busy)
                  const CircularProgressIndicator(strokeWidth: 1.5)
                else
                  TextlogButton('send code →', onPressed: _requestCode),
              ],
            ),
          ] else ...[
            const FieldLabel('code'),
            TextlogField(
              controller: _code,
              hint: '123456',
              autofocus: true,
              maxLength: 6,
              keyboardType: TextInputType.number,
              onSubmitted: (_) => _verify(),
            ),
            const SizedBox(height: space4),
            Row(
              children: [
                if (_busy)
                  const CircularProgressIndicator(strokeWidth: 1.5)
                else
                  TextlogButton('enter →', onPressed: _verify),
                const SizedBox(width: space4),
                GestureDetector(
                  onTap: () => setState(() => _sent = false),
                  child: Text('use a different address', style: theme.bodySmall!.asLink(palette)),
                ),
              ],
            ),
          ],

          if (_writesUnsupported) ...[
            const SizedBox(height: space6),
            Container(height: 1, color: palette.soft),
            const SizedBox(height: space5),
            Text('this server is read only', style: theme.bodySmall),
            const SizedBox(height: space2),
            Text(
              'It does not accept sign in from an app yet. Tell the app your handle to see your '
              'profile, and writing will keep opening textlog.cc in a browser.',
              style: theme.bodySmall!.copyWith(color: palette.quoteInk, height: 1.55),
            ),
            const SizedBox(height: space4),
            const FieldLabel('your handle'),
            TextlogField(controller: _handle, hint: 'handle', onSubmitted: (_) => _useHandle()),
            const SizedBox(height: space4),
            Row(
              children: [
                TextlogButton('continue →', onPressed: _useHandle),
                const SizedBox(width: space4),
                GestureDetector(
                  onTap: () => openLogin(ref),
                  child: Text('open textlog.cc', style: theme.bodySmall!.asLink(palette)),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
