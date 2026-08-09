import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../data/api.dart';
import '../../state/identity.dart';
import '../../state/session.dart';
import '../screens/web_action.dart';
import '../theme.dart';

/// Everything to do with who you are: your profile, account settings, and the way
/// out. Account settings still live on textlog.cc, so those open a browser tab.
Future<void> showAccount(BuildContext context, {String? path}) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  builder: (_) => _Account(path: path),
);

class _Account extends ConsumerWidget {
  const _Account({this.path});

  /// The page currently on screen, so "open on textlog.cc" lands in the same place.
  final String? path;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;
    final session = ref.watch(sessionProvider).valueOrNull;
    final handle = session?.account.handle ?? ref.watch(identityProvider).valueOrNull;

    Widget item(String label, VoidCallback onTap, {Color? colour}) => GestureDetector(
      onTap: () {
        Navigator.of(context).pop();
        onTap();
      },
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: space3),
        child: Text(label, style: theme.bodyMedium!.asLink(palette).copyWith(color: colour)),
      ),
    );

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(top: BorderSide(color: palette.soft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: gutterOf(context), vertical: space5),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text.rich(
                TextSpan(
                  children: [
                    TextSpan(text: '@', style: TextStyle(color: palette.accent)),
                    TextSpan(text: handle ?? 'not signed in'),
                  ],
                ),
                style: theme.titleLarge,
              ),
              if (session != null && !session.account.canPost) ...[
                const SizedBox(height: space2),
                Text(
                  'Verify your email address before posting.',
                  style: theme.labelSmall!.copyWith(color: palette.errorInk, height: 1.5),
                ),
              ],
              const SizedBox(height: space3),
              if (handle != null) item('your profile', () => context.push('/me')),
              if (handle == null) item('sign in', () => context.push('/me')),
              item('account settings', () => openAccount(ref)),
              item('browser sessions', () => openSessions(ref)),
              item(
                'open on textlog.cc',
                () => launchUrl(
                  Uri.parse('$textlogOrigin${path ?? '/'}'),
                  mode: LaunchMode.externalApplication,
                ),
              ),
              if (handle != null)
                item('log out', () async {
                  await ref.read(sessionProvider.notifier).signOut();
                  await ref.read(identityProvider.notifier).forget();
                }, colour: palette.errorInk),
            ],
          ),
        ),
      ),
    );
  }
}
