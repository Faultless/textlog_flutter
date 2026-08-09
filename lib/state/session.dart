import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../core/models.dart';
import 'providers.dart';

/// A signed-in session, or null. The token is an ordinary textlog session and is
/// revocable from account security on the website like any other.
///
/// Writing natively needs a server with the write endpoints. Against one without
/// them, signing in fails and the app keeps handing writes to the browser.
final sessionProvider = AsyncNotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<Session?> {
  static const _tokenKey = 'session_token';
  static const _handleKey = 'session_handle';

  @override
  Future<Session?> build() async {
    try {
      final preferences = await SharedPreferences.getInstance();
      final token = preferences.getString(_tokenKey);
      if (token == null) return null;

      // Confirm the token still works, and pick up any change to the account.
      final account = await ref.read(apiProvider).me(token);
      return Session(token: token, expiresAt: DateTime.now(), account: account);
    } on ApiFailure {
      await _clear();
      return null;
    } catch (_) {
      // Offline. Trust what we stored rather than signing the reader out.
      final preferences = await SharedPreferences.getInstance();
      final token = preferences.getString(_tokenKey);
      final handle = preferences.getString(_handleKey);
      if (token == null || handle == null) return null;
      return Session(
        token: token,
        expiresAt: DateTime.now(),
        account: Account(handle: handle, bio: '', canPost: true),
      );
    }
  }

  Future<void> requestCode(String email) => ref.read(apiProvider).requestCode(email);

  Future<void> verify(String email, String code) async {
    final session = await ref.read(apiProvider).verifyCode(email, code);
    final preferences = await SharedPreferences.getInstance();
    await preferences.setString(_tokenKey, session.token);
    await preferences.setString(_handleKey, session.account.handle);
    state = AsyncData(session);
  }

  Future<void> signOut() async {
    final token = state.valueOrNull?.token;
    state = const AsyncData(null);
    await _clear();
    if (token != null) {
      try {
        await ref.read(apiProvider).signOut(token);
      } catch (_) {
        // The local token is gone either way.
      }
    }
  }

  Future<void> refresh() async {
    final token = state.valueOrNull?.token;
    if (token == null) return;
    state = AsyncData(
      Session(token: token, expiresAt: DateTime.now(), account: await ref.read(apiProvider).me(token)),
    );
  }

  Future<void> _clear() async {
    final preferences = await SharedPreferences.getInstance();
    await preferences.remove(_tokenKey);
    await preferences.remove(_handleKey);
  }
}

/// The handle the app is acting as, from a real session or the handle you typed.
final viewerHandleProvider = Provider<String?>((ref) {
  return ref.watch(sessionProvider).valueOrNull?.account.handle;
});
