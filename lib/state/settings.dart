import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

final class Settings {
  const Settings({
    this.theme = ThemeChoice.system,
    this.accent = AccentChoice.theme,
    this.markdown = false,
  });

  final ThemeChoice theme;
  final AccentChoice accent;

  /// Off by default, because textlog.cc itself renders bodies as plain text — on
  /// means the app shows formatting the author did not necessarily get.
  final bool markdown;

  Settings copyWith({ThemeChoice? theme, AccentChoice? accent, bool? markdown}) => Settings(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    markdown: markdown ?? this.markdown,
  );
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<Settings> {
  static const _themeKey = 'theme';
  static const _accentKey = 'accent';
  static const _markdownKey = 'markdown';

  @override
  Future<Settings> build() async {
    // Appearance is a preference, not a requirement. If storage is unavailable the
    // app still opens, on the defaults.
    try {
      final preferences = await SharedPreferences.getInstance();
      return Settings(
        theme: ThemeChoice.fromId(preferences.getString(_themeKey)),
        accent: AccentChoice.fromId(preferences.getString(_accentKey)),
        markdown: preferences.getBool(_markdownKey) ?? false,
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

  Future<void> setMarkdown(bool enabled) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(markdown: enabled));
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(_markdownKey, enabled);
    } catch (_) {
      // Applies for this session regardless; persisting is best effort.
    }
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
