import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/session.dart';
import 'screens/home.dart';
import 'screens/me.dart';
import 'screens/profile.dart';
import 'screens/search.dart';
import 'screens/tag.dart';
import 'screens/thread.dart';

/// Paths mirror textlog.cc, so every screen has a shareable URL on web and the
/// "open on textlog.cc" action is a straight passthrough.
///
/// The router needs the session to answer `/`, which the site answers differently
/// depending on whether you are signed in, so it is built from a ref rather than
/// being a top-level constant.
GoRouter buildRouter(Ref ref) => GoRouter(
  initialLocation: '/',
  routes: [
    GoRoute(
      path: '/',
      redirect: (_, _) =>
          homeRedirect(signedIn: ref.read(sessionProvider).valueOrNull != null),
    ),
    for (final tab in HomeTab.values)
      GoRoute(path: tab.path, builder: (_, _) => HomeScreen(tab: tab)),
    GoRoute(path: '/me', builder: (_, _) => const MeScreen()),
    GoRoute(
      path: '/search',
      builder: (_, state) => SearchScreen(initialQuery: state.uri.queryParameters['q']),
    ),
    GoRoute(
      path: '/post/:id',
      builder: (_, state) => ThreadScreen(
        id: int.parse(state.pathParameters['id']!),
        flat: state.uri.queryParameters['view'] == 'flat',
      ),
    ),
    GoRoute(
      path: '/u/:handle',
      builder: (_, state) => ProfileScreen(
        handle: state.pathParameters['handle']!.toLowerCase(),
        tab: ProfileTab.fromName(state.uri.queryParameters['tab']),
      ),
    ),
    GoRoute(
      path: '/tag/:tag',
      builder: (_, state) => TagScreen(tag: state.pathParameters['tag']!.toLowerCase()),
      routes: [
        GoRoute(
          path: 'followers',
          builder: (_, state) =>
              TagFollowersScreen(tag: state.pathParameters['tag']!.toLowerCase()),
        ),
      ],
    ),
  ],
);

final routerProvider = Provider<GoRouter>((ref) {
  final router = buildRouter(ref);
  ref.onDispose(router.dispose);
  return router;
});
