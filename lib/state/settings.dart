import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

final class Settings {
  const Settings({this.theme = ThemeChoice.system, this.accent = AccentChoice.theme});

  final ThemeChoice theme;
  final AccentChoice accent;

  Settings copyWith({ThemeChoice? theme, AccentChoice? accent}) =>
      Settings(theme: theme ?? this.theme, accent: accent ?? this.accent);
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<Settings> {
  static const _themeKey = 'theme';
  static const _accentKey = 'accent';

  @override
  Future<Settings> build() async {
    // Appearance is a preference, not a requirement. If storage is unavailable the
    // app still opens, on the defaults.
    try {
      final preferences = await SharedPreferences.getInstance();
      return Settings(
        theme: ThemeChoice.fromId(preferences.getString(_themeKey)),
        accent: AccentChoice.fromId(preferences.getString(_accentKey)),
      );
    } catch (_) {
      return const Settings();
    }
  }

  Future<void> setTheme(ThemeChoice theme) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(theme: theme));
    await _write(_themeKey, theme.id);
  }

  Future<void> setAccent(AccentChoice accent) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(accent: accent));
    await _write(_accentKey, accent.id);
  }

  Future<void> _write(String key, String value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setString(key, value);
    } catch (_) {
      // The choice already applies for this session; persisting is best effort.
    }
  }
}
