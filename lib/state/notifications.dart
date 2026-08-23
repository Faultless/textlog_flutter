import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/notification_plan.dart';
import '../data/background.dart';
import '../data/local_store.dart';
import '../data/notifications.dart';

/// The notification setting, and the scheduling that follows from it.
///
/// Turning it on is the only thing that asks for permission or schedules any
/// background work: an app that registers a periodic task nobody asked for is an app
/// that drains a battery for nothing.
final notifyProvider = AsyncNotifierProvider<NotifyNotifier, NotifyPreferences>(
  NotifyNotifier.new,
);

/// Whether this build can raise notifications at all. Web cannot, and the setting is
/// hidden rather than shown broken.
final notifySupportedProvider = Provider<bool>((ref) => Notifications.supported);

class NotifyNotifier extends AsyncNotifier<NotifyPreferences> {
  @override
  Future<NotifyPreferences> build() => LocalStore.preferences();

  /// Turn the whole thing on or off.
  ///
  /// Returns false when permission was refused, so the caller can say so rather than
  /// leaving a switch on that will never fire.
  Future<bool> setEnabled(bool enabled) async {
    final current = state.valueOrNull ?? NotifyPreferences.off;

    if (!enabled) {
      await _save(current.copyWith(enabled: false));
      await Background.cancel();
      await Notifications.clearAll();
      return true;
    }

    if (!await Notifications.requestPermission()) {
      // Leave it off. A switch that is on while the OS refuses is a lie.
      await _save(current.copyWith(enabled: false));
      return false;
    }

    // A first turn-on gets everything; a later one keeps what was chosen before.
    final kinds = current.kinds.isEmpty ? NotifyPreferences.defaults.kinds : current.kinds;
    await _save(NotifyPreferences(enabled: true, kinds: kinds));
    await Background.schedule();
    return true;
  }

  Future<void> toggleKind(NotifyKind kind, bool wanted) async {
    final current = state.valueOrNull ?? NotifyPreferences.off;
    final kinds = {...current.kinds};
    wanted ? kinds.add(kind) : kinds.remove(kind);
    await _save(current.copyWith(kinds: kinds));
  }

  Future<void> _save(NotifyPreferences value) async {
    state = AsyncData(value);
    await LocalStore.savePreferences(value);
  }

  /// Signing out has to stop the polling as well, or the app keeps waking up to ask
  /// about an account it no longer has a token for.
  Future<void> signedOut() async {
    await _save((state.valueOrNull ?? NotifyPreferences.off).copyWith(enabled: false));
    await Background.cancel();
    await Notifications.clearAll();
    await LocalStore.forgetAnnounced();
  }
}
