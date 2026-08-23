import 'package:shared_preferences/shared_preferences.dart';

import '../core/notification_plan.dart';

/// Everything the app keeps on the device, in one place.
///
/// This exists because notifications are raised from a **background isolate**, which
/// has no access to the providers the rest of the app reads. That isolate needs the
/// session token, the reader's handle and the notification preferences, so those keys
/// cannot live privately inside a notifier any more — two copies of a key string is
/// exactly the bug that makes a background poll silently do nothing.
///
/// Every read tolerates storage being unavailable. Losing a preference is cosmetic;
/// failing to open is not.
abstract final class LocalStore {
  static const _token = 'session_token';
  static const _handle = 'session_handle';
  static const _notifyEnabled = 'notify_enabled';
  static const _notifyKinds = 'notify_kinds';
  static const _announced = 'notify_announced';

  /// How many announced ids to remember. A poll only ever sees one page of activity,
  /// so this is comfortably more than enough to stop a repeat, and it is bounded so a
  /// phone left running for a year does not accumulate forever.
  static const announcedLimit = 300;

  static Future<SharedPreferences?> _open() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  // -- session ---------------------------------------------------------------

  static Future<String?> token() async => (await _open())?.getString(_token);

  static Future<String?> handle() async => (await _open())?.getString(_handle);

  static Future<void> saveSession(String token, String handle) async {
    final preferences = await _open();
    await preferences?.setString(_token, token);
    await preferences?.setString(_handle, handle);
  }

  static Future<void> clearSession() async {
    final preferences = await _open();
    await preferences?.remove(_token);
    await preferences?.remove(_handle);
  }

  // -- notification preferences ---------------------------------------------

  static Future<NotifyPreferences> preferences() async {
    final preferences = await _open();
    if (preferences == null) return NotifyPreferences.off;
    final kinds = preferences.getStringList(_notifyKinds);
    return NotifyPreferences(
      enabled: preferences.getBool(_notifyEnabled) ?? false,
      kinds: kinds == null
          // Never set: whatever the reader gets on first turning it on.
          ? NotifyPreferences.defaults.kinds
          : {for (final id in kinds) ?NotifyKind.fromId(id)},
    );
  }

  static Future<void> savePreferences(NotifyPreferences value) async {
    final preferences = await _open();
    await preferences?.setBool(_notifyEnabled, value.enabled);
    await preferences?.setStringList(
      _notifyKinds,
      [for (final kind in value.kinds) kind.id],
    );
  }

  // -- what has already been said -------------------------------------------

  static Future<Set<String>> announced() async =>
      (await _open())?.getStringList(_announced)?.toSet() ?? {};

  /// Add to the remembered set, keeping the newest [announcedLimit].
  static Future<void> remember(Set<String> ids) async {
    if (ids.isEmpty) return;
    final preferences = await _open();
    if (preferences == null) return;
    final held = preferences.getStringList(_announced) ?? const <String>[];
    // Newest last, so trimming from the front drops the oldest.
    final merged = [...held.where((id) => !ids.contains(id)), ...ids];
    final trimmed = merged.length > announcedLimit
        ? merged.sublist(merged.length - announcedLimit)
        : merged;
    await preferences.setStringList(_announced, trimmed);
  }

  /// Forget the lot — on sign out, so signing back in does not replay a backlog.
  static Future<void> forgetAnnounced() async {
    await (await _open())?.remove(_announced);
  }
}
