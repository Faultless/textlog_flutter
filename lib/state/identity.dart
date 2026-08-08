import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The handle the user has told us is theirs.
///
/// This is **identity, not authentication**. The app holds no session and cannot get
/// one: textlog signs you in by emailing a magic link, that link opens in your
/// browser, and neither Chrome Custom Tabs nor SFSafariViewController lets an app
/// read the browser's cookies — that isolation is exactly what makes the link work.
///
/// For a read-only client that is enough. Nothing here is gated on being signed in,
/// so a handle only answers "whose profile does *you* mean". Writing still happens on
/// textlog.cc, where the real session lives.
final identityProvider = AsyncNotifierProvider<IdentityNotifier, String?>(
  IdentityNotifier.new,
);

/// The server's own rule, from `/api/v1/users/{handle}`.
final handlePattern = RegExp(r'^[A-Za-z0-9_]{2,24}$');

class IdentityNotifier extends AsyncNotifier<String?> {
  static const _key = 'handle';

  @override
  Future<String?> build() async {
    // Losing the stored handle is a cosmetic problem; blocking every screen behind
    // a storage error is not. Treat a failure as "we don't know who you are".
    try {
      final preferences = await SharedPreferences.getInstance();
      return preferences.getString(_key);
    } catch (_) {
      return null;
    }
  }

  Future<void> remember(String handle) async {
    final normalized = handle.trim().replaceFirst('@', '').toLowerCase();
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_key, normalized);
    state = AsyncData(normalized);
  }

  Future<void> forget() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_key);
    state = const AsyncData(null);
  }
}
