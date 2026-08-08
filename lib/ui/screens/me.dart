import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../state/identity.dart';
import '../../state/providers.dart';
import '../theme.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';
import 'profile.dart';
import 'web_action.dart';

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final identity = ref.watch(identityProvider);

    // A handle we cannot read is the same as not having one — never leave the screen
    // spinning on it.
    return switch (identity) {
      AsyncData(value: final handle?) => ProfileScreen(handle: handle, isSelf: true),
      AsyncLoading() => Scaffold(
        appBar: textlogAppBar(context, path: '/enter', showBack: true),
        body: const Spinner(),
      ),
      _ => Scaffold(
        appBar: textlogAppBar(context, path: '/enter', showBack: true),
        body: const SingleChildScrollView(child: _Introduce()),
      ),
    };
  }
}

/// The app has no session and cannot get one, so this asks who you are rather than
/// pretending to log you in. Being straight about that is the whole design here —
/// anything else would imply the app can see your account when it cannot.
class _Introduce extends ConsumerStatefulWidget {
  const _Introduce();

  @override
  ConsumerState<_Introduce> createState() => _IntroduceState();
}

class _IntroduceState extends ConsumerState<_Introduce> {
  final _controller = TextEditingController();
  String? _error;
  var _checking = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final handle = _controller.text.trim().replaceFirst('@', '');
    if (!handlePattern.hasMatch(handle)) {
      setState(() => _error = 'Handles are 2–24 letters, numbers or underscores.');
      return;
    }

    setState(() {
      _checking = true;
      _error = null;
    });

    // Confirm the account exists before saving it, so a typo fails here rather than
    // leaving you pointed at an empty profile forever.
    try {
      await ref.read(apiProvider).profile(handle);
      await ref.read(identityProvider.notifier).remember(handle);
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() => _error = failure.isNotFound ? 'No such handle on textlog.' : failure.message);
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Could not reach textlog.');
    } finally {
      if (mounted) setState(() => _checking = false);
    }
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
          Text('you', style: theme.titleLarge),
          const SizedBox(height: space4),
          Text(
            'textlog signs you in by emailing a link, and that link opens in your '
            'browser. This app cannot read your browser’s session, so it does not '
            'have an account of its own.\n\n'
            'Tell it your handle and it will show you your profile. Writing still '
            'happens on textlog.cc, where you are actually signed in.',
            style: theme.bodyMedium!.copyWith(color: palette.quoteInk),
          ),
          const SizedBox(height: space5),
          TextField(
            controller: _controller,
            autocorrect: false,
            enableSuggestions: false,
            style: theme.bodyMedium,
            onSubmitted: (_) => _submit(),
            decoration: InputDecoration(
              prefixText: '@',
              prefixStyle: theme.bodyMedium!.copyWith(color: palette.accent),
              hintText: 'your handle',
              hintStyle: theme.bodyMedium!.copyWith(color: palette.muted),
              errorText: _error,
              errorStyle: theme.labelSmall!.copyWith(color: palette.errorInk),
              enabledBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: palette.soft),
              ),
              focusedBorder: UnderlineInputBorder(
                borderSide: BorderSide(color: palette.accent),
              ),
            ),
          ),
          const SizedBox(height: space5),
          Row(
            children: [
              TextButton(
                onPressed: _checking ? null : _submit,
                style: TextButton.styleFrom(
                  backgroundColor: palette.accent,
                  foregroundColor: palette.bg,
                  shape: const RoundedRectangleBorder(),
                  padding: const EdgeInsets.symmetric(horizontal: space4, vertical: space3),
                ),
                child: Text(_checking ? 'checking…' : 'continue', style: theme.bodySmall),
              ),
              const SizedBox(width: space4),
              GestureDetector(
                onTap: () => openLogin(ref),
                child: Text(
                  'log in on textlog.cc',
                  style: theme.bodySmall!.asLink(palette),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
