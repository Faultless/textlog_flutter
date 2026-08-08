import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'state/pending_write.dart';
import 'state/settings.dart';
import 'ui/router.dart';
import 'ui/theme.dart';

void main() {
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
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Coming back from the browser is the only signal we get that a reply or post
    // may have landed.
    if (state == AppLifecycleState.resumed) {
      ref.read(pendingWriteProvider.notifier).settle();
    }
  }

  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider).valueOrNull ?? const Settings();

    ThemeData themed(Palette palette) => textlogTheme(
      palette.withAccent(settings.accent.forBrightness(palette.brightness)),
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
      routerConfig: router,
    );
  }
}
