import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The last page of a feed, kept on the device so a cold start has something to
/// show.
///
/// Without this, opening the app means an empty screen with a spinner on it while a
/// request goes out — every time, including the nine times out of ten when the posts
/// you are about to be shown are the ones you were shown before. The stored page
/// goes up immediately and the network refresh replaces it when it lands.
///
/// What is stored is the server's own JSON, trimmed. Parsing it back through the
/// same `Page.fromJson` the network path uses means there is no second serialiser to
/// drift out of step with the model — a stored feed either decodes exactly or it is
/// thrown away.
abstract final class FeedStore {
  /// Enough to fill a screen and a bit of scroll. The point is to have something up
  /// instantly, not to keep a session's worth of reading on disk.
  static const limit = 20;

  /// Past this, a stored feed is not worth showing: posts have a relative timestamp,
  /// and `3h` on a week-old post is a lie the refresh would only fix afterwards.
  static const shelfLife = Duration(days: 2);

  static const _stamp = ':saved_at';

  static Future<SharedPreferences?> _open() async {
    try {
      return await SharedPreferences.getInstance();
    } catch (_) {
      return null;
    }
  }

  /// Keep [json] as [key]'s stored page, trimmed to [limit] posts.
  static Future<void> save(String key, Map<String, dynamic> json, {DateTime? now}) async {
    final preferences = await _open();
    if (preferences == null) return;

    final data = json['data'];
    if (data is! List) return;
    final trimmed = {
      ...json,
      'data': data.take(limit).toList(),
      // The cursor belongs to the *whole* page the server sent. Keeping it after
      // trimming would page from the wrong place, skipping whatever was cut.
      'pagination': data.length > limit ? const {'next_cursor': null} : json['pagination'],
    };

    try {
      await preferences.setString(key, jsonEncode(trimmed));
      await preferences.setInt(
        '$key$_stamp',
        (now ?? DateTime.now()).millisecondsSinceEpoch,
      );
    } catch (_) {
      // A feed we could not keep is not a feed we cannot fetch.
    }
  }

  /// [key]'s stored page, or null when there is none, it has aged out, or it will
  /// not parse.
  static Future<Map<String, dynamic>?> load(String key, {DateTime? now}) async {
    final preferences = await _open();
    final stored = preferences?.getString(key);
    if (stored == null) return null;

    final savedAt = preferences?.getInt('$key$_stamp');
    if (savedAt == null) return null;
    final age = (now ?? DateTime.now())
        .difference(DateTime.fromMillisecondsSinceEpoch(savedAt));
    // A clock that went backwards makes `age` negative; that is not freshness.
    if (age.isNegative || age > shelfLife) return null;

    try {
      final json = jsonDecode(stored);
      return json is Map<String, dynamic> ? json : null;
    } catch (_) {
      // Written by an older version, or truncated. Not worth keeping.
      return null;
    }
  }

  /// Drop every stored feed. For signing out, where the next reader of this device
  /// should not inherit the last one's timeline.
  static Future<void> clear(Iterable<String> keys) async {
    final preferences = await _open();
    if (preferences == null) return;
    for (final key in keys) {
      await preferences.remove(key);
      await preferences.remove('$key$_stamp');
    }
  }
}
