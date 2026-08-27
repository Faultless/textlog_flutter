import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../ui/theme.dart';

final class Settings {
  const Settings({
    this.theme = ThemeChoice.system,
    this.accent = AccentChoice.theme,
    this.markdown = false,
    this.font = FontChoice.jetbrains,
    this.textSize = TextSize.regular,
    this.barebones = false,
    this.translate = true,
    this.timestamps = true,
    this.replyCounts = true,
    this.followNotices = true,
    this.swipeToReply = true,
    this.tabOrder = const [],
    this.hiddenTabs = const {},
  });

  final ThemeChoice theme;
  final AccentChoice accent;

  /// Extra block markdown — headings, lists, tables, quotes. Off by default because
  /// textlog.cc keeps a post body flat, so on means the app shows structure the
  /// author did not necessarily get. Code, TeX, links and strikethrough are not
  /// covered by this: the site renders those, so the app always does too.
  final bool markdown;
  final FontChoice font;
  final TextSize textSize;

  /// Strip the app back to characters and rules: no icons, no ripples, no filled
  /// buttons, no switches, no spinners, no page slides.
  final bool barebones;

  /// Offer to translate a post the server found was not English. Cheap to leave on:
  /// nothing is shown unless the server already stored a translation.
  final bool translate;

  /// Reading preferences with no counterpart on the site. They exist because a phone
  /// is a smaller page than a browser window, and because a reader who does not want
  /// to know how many replies a post has should not have to.
  final bool timestamps;
  final bool replyCounts;

  /// Follows and tag-follows in the `for you` feed. Reading about who followed whom
  /// is not the same activity as reading posts, and some readers want only the posts.
  final bool followNotices;

  /// Drag a post sideways to reply to it. On by default — it is additive, and the
  /// reply link stays exactly where it was for anyone who never discovers it.
  final bool swipeToReply;

  /// The reader's own tab order, by id, and the ones they turned off. Empty order
  /// means "as shipped"; a tab missing from a non-empty order is appended, so a tab
  /// added by a later version appears rather than vanishing.
  final List<String> tabOrder;
  final Set<String> hiddenTabs;

  Chrome get chrome => Chrome(plain: barebones, scale: textSize.scale);

  Settings copyWith({
    ThemeChoice? theme,
    AccentChoice? accent,
    bool? markdown,
    FontChoice? font,
    TextSize? textSize,
    bool? barebones,
    bool? translate,
    bool? timestamps,
    bool? replyCounts,
    bool? followNotices,
    bool? swipeToReply,
    List<String>? tabOrder,
    Set<String>? hiddenTabs,
  }) => Settings(
    theme: theme ?? this.theme,
    accent: accent ?? this.accent,
    markdown: markdown ?? this.markdown,
    font: font ?? this.font,
    textSize: textSize ?? this.textSize,
    barebones: barebones ?? this.barebones,
    translate: translate ?? this.translate,
    timestamps: timestamps ?? this.timestamps,
    replyCounts: replyCounts ?? this.replyCounts,
    followNotices: followNotices ?? this.followNotices,
    swipeToReply: swipeToReply ?? this.swipeToReply,
    tabOrder: tabOrder ?? this.tabOrder,
    hiddenTabs: hiddenTabs ?? this.hiddenTabs,
  );
}

final settingsProvider = AsyncNotifierProvider<SettingsNotifier, Settings>(
  SettingsNotifier.new,
);

class SettingsNotifier extends AsyncNotifier<Settings> {
  static const _themeKey = 'theme';
  static const _accentKey = 'accent';
  static const _markdownKey = 'markdown';
  static const _fontKey = 'font';
  static const _textSizeKey = 'text_size';
  static const _barebonesKey = 'barebones';
  static const _translateKey = 'translate';
  static const _timestampsKey = 'timestamps';
  static const _replyCountsKey = 'reply_counts';
  static const _followNoticesKey = 'follow_notices';
  static const _swipeToReplyKey = 'swipe_to_reply';
  static const _tabOrderKey = 'tab_order';
  static const _hiddenTabsKey = 'hidden_tabs';

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
        font: FontChoice.fromId(preferences.getString(_fontKey)),
        textSize: TextSize.fromId(preferences.getString(_textSizeKey)),
        barebones: preferences.getBool(_barebonesKey) ?? false,
        translate: preferences.getBool(_translateKey) ?? true,
        timestamps: preferences.getBool(_timestampsKey) ?? true,
        replyCounts: preferences.getBool(_replyCountsKey) ?? true,
        followNotices: preferences.getBool(_followNoticesKey) ?? true,
        swipeToReply: preferences.getBool(_swipeToReplyKey) ?? true,
        tabOrder: preferences.getStringList(_tabOrderKey) ?? const [],
        hiddenTabs: (preferences.getStringList(_hiddenTabsKey) ?? const []).toSet(),
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

  Future<void> setFont(FontChoice font) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(font: font));
    await _write(_fontKey, font.id);
  }

  Future<void> setTextSize(TextSize size) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(textSize: size));
    await _write(_textSizeKey, size.id);
  }

  Future<void> setMarkdown(bool enabled) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(markdown: enabled));
    await _writeFlag(_markdownKey, enabled);
  }

  Future<void> setBarebones(bool enabled) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(barebones: enabled));
    await _writeFlag(_barebonesKey, enabled);
  }

  Future<void> setTranslate(bool enabled) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(translate: enabled));
    await _writeFlag(_translateKey, enabled);
  }

  Future<void> setTimestamps(bool enabled) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(timestamps: enabled));
    await _writeFlag(_timestampsKey, enabled);
  }

  Future<void> setReplyCounts(bool enabled) async {
    state = AsyncData((state.valueOrNull ?? const Settings()).copyWith(replyCounts: enabled));
    await _writeFlag(_replyCountsKey, enabled);
  }

  Future<void> setFollowNotices(bool enabled) async {
    state = AsyncData(
      (state.valueOrNull ?? const Settings()).copyWith(followNotices: enabled),
    );
    await _writeFlag(_followNoticesKey, enabled);
  }

  Future<void> setSwipeToReply(bool enabled) async {
    state = AsyncData(
      (state.valueOrNull ?? const Settings()).copyWith(swipeToReply: enabled),
    );
    await _writeFlag(_swipeToReplyKey, enabled);
  }

  Future<void> setTabs({List<String>? order, Set<String>? hidden}) async {
    final current = state.valueOrNull ?? const Settings();
    state = AsyncData(current.copyWith(
      tabOrder: order ?? current.tabOrder,
      hiddenTabs: hidden ?? current.hiddenTabs,
    ));
    await _writeList(_tabOrderKey, order ?? current.tabOrder);
    await _writeList(_hiddenTabsKey, (hidden ?? current.hiddenTabs).toList());
  }

  Future<void> _writeList(String key, List<String> value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setStringList(key, value);
    } catch (_) {
      // Applies for this session regardless; persisting is best effort.
    }
  }

  Future<void> _writeFlag(String key, bool value) async {
    try {
      final preferences = await SharedPreferences.getInstance();
      await preferences.setBool(key, value);
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
