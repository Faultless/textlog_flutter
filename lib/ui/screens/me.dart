import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/identity.dart';
import '../../state/session.dart';
import '../widgets/shell.dart';
import '../widgets/status.dart';
import 'profile.dart';
import 'sign_in.dart';

class MeScreen extends ConsumerWidget {
  const MeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionProvider);
    final identity = ref.watch(identityProvider);

    if (session.isLoading || identity.isLoading) {
      return Scaffold(
        appBar: textlogAppBar(context, path: '/enter', showBack: true),
        body: const Spinner(),
      );
    }

    final handle = session.valueOrNull?.account.handle ?? identity.valueOrNull;
    if (handle != null) return ProfileScreen(handle: handle, isSelf: true);

    return Scaffold(
      appBar: textlogAppBar(context, path: '/enter', showBack: true),
      body: const ReadingColumn(child: SingleChildScrollView(child: SignInCard())),
    );
  }
}
