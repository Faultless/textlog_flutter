import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_web_plugins/url_strategy.dart';
import 'package:go_router/go_router.dart';

import 'ui/router.dart';
import 'ui/theme.dart';

void main() {
  // Without this, web URLs are hash-based and /tag/open_source never reaches the
  // router. No-op off the web.
  usePathUrlStrategy();

  // `push` keeps the back stack but otherwise leaves the address bar behind, so
  // tapping into a thread on web would give you a URL for the page you just left.
  GoRouter.optionURLReflectsImperativeAPIs = true;

  if (kIsWeb) {
    // Flutter web paints into a canvas, so without a published semantics tree the
    // page is opaque to screen readers and to browser automation alike. textlog
    // itself is markup-first and accessible; match that.
    WidgetsFlutterBinding.ensureInitialized();
    SemanticsBinding.instance.ensureSemantics();
  }

  runApp(const ProviderScope(child: TextlogApp()));
}

class TextlogApp extends StatelessWidget {
  const TextlogApp({super.key});

  @override
  Widget build(BuildContext context) => MaterialApp.router(
    title: 'textlog',
    debugShowCheckedModeBanner: false,
    theme: textlogTheme(Brightness.light),
    darkTheme: textlogTheme(Brightness.dark),
    routerConfig: router,
  );
}
