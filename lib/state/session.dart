import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../data/local_store.dart';
import 'notifications.dart';
import 'providers.dart';

/// A signed-in session, or null. The token is an ordinary textlog session and is
/// revocable from account security on the website like any other.
///
/// Writing natively needs a server with the write endpoints. Against one without
/// them, signing in fails and the app keeps handing writes to the browser.
final sessionProvider = AsyncNotifierProvider<SessionNotifier, Session?>(SessionNotifier.new);

class SessionNotifier extends AsyncNotifier<Session?> {
  @override
  Future<Session?> build() async {
    // What the device already knows, without waiting for anything. Storage was
    // opened before the first frame, so this is available immediately — and that is
    // the difference between opening the app signed in and watching it decide.
    if (LocalStore.primedSession() case final stored?) {
      _confirm(stored.token);
      return stored;
    }

    try {
      final token = await LocalStore.token();
      if (token == null) return null;

      // Confirm the token still works, and pick up any change to the account.
      final account = await ref.read(apiProvider).me(token);
      return Session(token: token, expiresAt: DateTime.now(), account: account);
    } on ApiFailure catch (failure) {
      // Only a rejected token means the session is gone.
      if (!failure.isUnauthorized) return _stored();
      await _clear();
      return null;
    } catch (_) {
      // Offline, or the request timed out. Trust what we stored.
      return _stored();
    }
  }

  /// Check the stored token behind the reader's back, and fill in the rest of the
  /// account — the stored copy is only a handle, since that is all the background
  /// poller ever needed.
  ///
  /// Deliberately not awaited by [build]: a slow or absent network must not hold up
  /// a session the device is already sure of. Only a *rejected* token clears it;
  /// being offline is not evidence that anyone signed out.
  Future<void> _confirm(String token) async {
    try {
      final account = await ref.read(apiProvider).me(token);
      final current = state.valueOrNull;
      // The reader may have signed out, or signed in as someone else, while this
      // was in flight. Whatever is current wins.
      if (current == null || current.token != token) return;
      state = AsyncData(current.withAccount(account));
    } on ApiFailure catch (failure) {
      if (!failure.isUnauthorized) return;
      if (state.valueOrNull?.token != token) return;
      await _clear();
      state = const AsyncData(null);
    } catch (_) {
      // Offline. What we stored still stands.
    }
  }

  /// What we last knew, for when the server cannot confirm it.
  Future<Session?> _stored() async {
    final token = await LocalStore.token();
    final handle = await LocalStore.handle();
    if (token == null || handle == null) return null;
    return Session(
      token: token,
      expiresAt: DateTime.now(),
      account: Account(handle: handle, bio: '', canPost: true),
    );
  }

  Future<void> requestCode(String email) => ref.read(apiProvider).requestCode(email);

  Future<void> verify(String email, String code) async {
    final session = await ref.read(apiProvider).verifyCode(email, code);
    await LocalStore.saveSession(session.token, session.account.handle);
    state = AsyncData(session);
  }

  Future<void> signOut() async {
    final token = state.valueOrNull?.token;
    state = const AsyncData(null);
    await _clear();
    // Stop the background poll too, or the app keeps waking up to ask about an
    // account it no longer holds a token for.
    await ref.read(notifyProvider.notifier).signedOut();
    if (token != null) {
      try {
        await ref.read(apiProvider).signOut(token);
      } catch (_) {
        // The local token is gone either way.
      }
    }
  }

  /// Write an account we just changed straight into the session, so the screen behind
  /// a sheet is already correct when it closes rather than flickering through a refetch.
  void noteAccount(Account account) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData(current.withAccount(account));
  }

  Future<void> refresh() async {
    final token = state.valueOrNull?.token;
    if (token == null) return;
    state = AsyncData(
      Session(token: token, expiresAt: DateTime.now(), account: await ref.read(apiProvider).me(token)),
    );
  }

  Future<void> _clear() => LocalStore.clearSession();
}

/// The session the app has, as far as it knows *right now*.
///
/// [sessionProvider] is asynchronous, and an `AsyncNotifier`'s first state is
/// `loading` even when its `build` returns without awaiting anything. Reading
/// `valueOrNull` there gives null, which is how a cold start came to draw a
/// signed-out app — `sign in` in the header, no account tabs — and then rearrange
/// itself a moment later.
///
/// So this falls back to what the device had stored, but only while the real answer
/// is still coming. Once it arrives, or once someone signs out, it is the only
/// answer: a cleared session is not a loading one.
///
/// **The UI reads this.** [sessionProvider] is for the token and for the actions on
/// its notifier; anything asking "who am I" or "am I signed in" wants this.
final viewerProvider = Provider<Session?>((ref) {
  final live = ref.watch(sessionProvider);
  return live.valueOrNull ?? (live.isLoading ? LocalStore.primedSession() : null);
});

/// Whether anyone is signed in — and nothing else.
///
/// Coarse on purpose. A feed has to refetch when you sign in or out, because the
/// answer genuinely differs, but *not* when the confirmation behind a cold start
/// fills in a bio. Watching the session itself would do both.
final signedInProvider = Provider<bool>((ref) => ref.watch(viewerProvider) != null);

/// The handle the app is acting as, from a real session or the handle you typed.
final viewerHandleProvider = Provider<String?>((ref) {
  return ref.watch(viewerProvider)?.account.handle;
});
