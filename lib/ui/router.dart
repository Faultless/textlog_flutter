import 'package:go_router/go_router.dart';

import 'screens/home.dart';
import 'screens/profile.dart';
import 'screens/tag.dart';
import 'screens/thread.dart';

/// Paths mirror textlog.cc, so every screen has a shareable URL on web and the
/// "open on textlog.cc" action is a straight passthrough.
final router = GoRouter(
  routes: [
    GoRoute(path: '/', builder: (_, _) => const HomeScreen(tab: 0)),
    GoRoute(path: '/hot', builder: (_, _) => const HomeScreen(tab: 1)),
    GoRoute(path: '/live', builder: (_, _) => const HomeScreen(tab: 2)),
    GoRoute(
      path: '/post/:id',
      builder: (_, state) => ThreadScreen(id: int.parse(state.pathParameters['id']!)),
    ),
    GoRoute(
      path: '/u/:handle',
      builder: (_, state) => ProfileScreen(handle: state.pathParameters['handle']!),
    ),
    GoRoute(
      path: '/tag/:tag',
      builder: (_, state) => TagScreen(tag: state.pathParameters['tag']!),
    ),
  ],
);
