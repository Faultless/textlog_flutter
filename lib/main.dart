import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'data/background.dart';
import 'data/local_store.dart';
import 'data/notifications.dart';
import 'state/pending_write.dart';
import 'state/settings.dart';
import 'ui/router.dart';
import 'ui/theme.dart';

Future<void> main() async {
  // Without this, web URLs are hash-based and /tag/open_source never reaches the
  // router. No-op off the web.
  usePathUrlStrategy();

  // `push` keeps the back stack but otherwise leaves the address bar behind, so
  // tapping into a thread on web would give you a URL for the page you just left.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  WidgetsFlutterBinding.ensureInitialized();

  if (kIsWeb) {
    // Flutter web paints into a canvas, so without a published semantics tree the
    // page is opaque to screen readers and to browser automation alike. textlog
    // itself is markup-first and accessible; match that.
    SemanticsBinding.instance.ensureSemantics();
  }

  // Wires the isolate entry points so a notification action works with the app
  // closed. Nothing is scheduled and no permission is asked for until the reader
  // turns the setting on.
  Background.ready();

  // Before the first frame: opening the app while already signed in should look like
  // being signed in, not like a signed-out app that changes its mind. See
  // LocalStore.prime.
  await LocalStore.prime();

  runApp(const ProviderScope(child: TextlogApp()));
}

class TextlogApp extends ConsumerStatefulWidget {
  const TextlogApp({super.key});

  @override
  ConsumerState<TextlogApp> createState() => _TextlogAppState();
}

class _TextlogAppState extends ConsumerState<TextlogApp> with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    Notifications.route.addListener(_followNotification);
    Notifications.replied.addListener(_settleReply);
    // Opened *by* a notification rather than tapped while running.
    Notifications.launchRoute().then((route) {
      if (route != null) Notifications.route.value = route;
    });
  }

  @override
  void dispose() {
    Notifications.route.removeListener(_followNotification);
    Notifications.replied.removeListener(_settleReply);
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// A tapped notification navigates once the router exists to do it.
  void _followNotification() {
    final route = Notifications.route.value;
    if (route == null || route.isEmpty) return;
    Notifications.route.value = null;
    ref.read(routerProvider).go(route);
  }

  /// A reply sent from the shade landed on the server, not through the app, so the
  /// thread it belongs to has to be told to catch up.
  void _settleReply() {
    final postId = Notifications.replied.value;
    if (postId == null) return;
    Notifications.replied.value = null;
    ref.read(pendingWriteProvider.notifier).expect(PendingReply(postId));
    ref.read(pendingWriteProvider.notifier).settle();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the browser is the only signal we get that a reply or post
    // may have landed.
    if (state == AppLifecycleState.resumed) {
      ref.read(pendingWriteProvider.notifier).settle();
      // A notification tapped while the app was suspended arrives around now.
      _followNotification();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? const Settings();

    ThemeData themed(Palette palette) => textlogTheme(
      palette.withAccent(settings.accent.forBrightness(palette.brightness)),
      settings.font,
      settings.chrome,
    );

    // `system` hands the light/dark decision to Flutter so it tracks the device
    // live; a fixed choice pins both slots to the same palette so it cannot.
    final (light, dark, mode) = switch (settings.theme) {
      ThemeChoice.system => (
        themed(Palette.light),
        themed(Palette.dark),
        ThemeMode.system,
      ),
      final choice => () {
        final palette = choice.resolve(Brightness.light);
        final theme = themed(palette);
        return (
          theme,
          theme,
          palette.brightness == Brightness.dark ? ThemeMode.dark : ThemeMode.light,
        );
      }(),
    };

    return MaterialApp.router(
      title: 'textlog',
      debugShowCheckedModeBanner: false,
      theme: light,
      darkTheme: dark,
      themeMode: mode,
      // Barebones means no animation, and a theme is not an exception: crossfading
      // into a mode whose whole point is that nothing moves would be a contradiction.
      themeAnimationDuration: settings.barebones ? Duration.zero : kThemeAnimationDuration,
      routerConfig: ref.watch(routerProvider),
    );
  }
}
