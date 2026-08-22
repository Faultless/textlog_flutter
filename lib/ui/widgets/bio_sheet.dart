import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/models.dart';
import '../../state/providers.dart';
import '../../state/session.dart';
import '../theme.dart';
import 'form_parts.dart';
import 'post_actions.dart';

/// The server's own limit, from `BIO_MAX`.
const bioMax = 280;

/// Editing your bio, natively. `PATCH /api/v1/me` is new; before it this was a trip
/// to account settings in a browser tab.
Future<void> showBioSheet(BuildContext context) => showModalBottomSheet<void>(
  context: context,
  backgroundColor: Colors.transparent,
  isScrollControlled: true,
  builder: (_) => const _BioSheet(),
);

class _BioSheet extends ConsumerStatefulWidget {
  const _BioSheet();

  @override
  ConsumerState<_BioSheet> createState() => _BioSheetState();
}

class _BioSheetState extends ConsumerState<_BioSheet> {
  late final _field = TextEditingController(
    text: ref.read(sessionProvider).valueOrNull?.account.bio ?? '',
  );
  var _busy = false;

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null || _busy) return;

    setState(() => _busy = true);
    try {
      final account = await ref.read(apiProvider).editBio(session.token, _field.text.trim());
      // Write it straight into the session and drop the cached profile, so the header
      // behind this sheet is already right when it closes.
      ref.read(sessionProvider.notifier).noteAccount(account);
      ref.invalidate(profileProvider(account.handle));
      if (mounted) Navigator.of(context).pop();
    } on ApiFailure catch (failure) {
      if (mounted) {
        setState(() => _busy = false);
        toast(context, failure.message);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final palette = context.palette;
    final theme = Theme.of(context).textTheme;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: palette.panel,
        border: Border(top: BorderSide(color: palette.soft)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          // Lifts with the keyboard, so the field never sits under it.
          padding: EdgeInsets.only(
            left: gutterOf(context),
            right: gutterOf(context),
            top: space5,
            bottom: space5 + MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('your bio', style: theme.titleLarge),
              const SizedBox(height: space2),
              Text(
                'Mentions, hashtags and links all work in here.',
                style: theme.labelSmall!.copyWith(color: palette.muted),
              ),
              const SizedBox(height: space4),
              TextlogField(
                controller: _field,
                hint: 'a line or two about you',
                maxLength: bioMax,
                minLines: 3,
                maxLines: 8,
                autofocus: true,
              ),
              const SizedBox(height: space4),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton(
                    onPressed: _busy ? null : () => Navigator.of(context).pop(),
                    child: Text(
                      'cancel',
                      style: theme.bodySmall!.copyWith(color: palette.muted),
                    ),
                  ),
                  const SizedBox(width: space2),
                  TextlogButton(
                    _busy ? 'saving…' : 'save →',
                    onPressed: _busy ? null : _save,
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
