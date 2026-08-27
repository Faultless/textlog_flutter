import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../core/app_links.dart';
import '../core/body_tokens.dart' show linkOrigin;

import '../state/session.dart';
import 'screens/drafts.dart';
import 'screens/explore.dart';
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
          homeRedirect(signedIn: ref.read(viewerProvider) != null),
    ),
    for (final tab in HomeTab.values)
      GoRoute(path: tab.path, builder: (_, _) => HomeScreen(tab: tab)),
    GoRoute(path: '/me', builder: (_, _) => const MeScreen()),
    GoRoute(path: '/drafts', builder: (_, _) => const DraftsScreen()),
    GoRoute(path: '/explore', builder: (_, _) => const ExploreScreen()),
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

/// Open a post, unless that is the page already on screen.
///
/// Several things navigate to a post: the card, its timestamp, a quoted parent, the
/// `top` link. On the page that post is *about*, every one of them pushes the route it
/// is already on — which stacks another copy of the same page, and a second tap
/// another, so a checklist item that fell through to the card read as an endless loop
/// of opening the same reply.
///
/// Guarding it here rather than at each call site means the next thing that navigates
/// to a post cannot reintroduce it. Checked on tap rather than during build, so a
/// widget can still be rendered in a test with no router above it.
void openPost(BuildContext context, int id) {
  final route = '/post/$id';
  // The query is deliberately ignored: flat and tree are the same page.
  if (GoRouterState.of(context).uri.path == route) return;
  context.push(route);
}

/// Follow a link from a post body, a preview card, or anywhere else in a body.
///
/// A link to this instance opens in the app; everything else goes to the browser.
/// Before this, tapping `/post/2201` in a body left the app for a page it already had
/// a screen for.
Future<void> openLink(BuildContext context, String url) async {
  final route = routeForUrl(url, origin: linkOrigin);
  if (route != null) {
    // Reuses the guard, so a link to the post you are reading does nothing rather
    // than stacking another copy of the same page.
    if (route.startsWith('/post/')) {
      final id = int.tryParse(route.substring('/post/'.length));
      if (id != null) return openPost(context, id);
    }
    if (GoRouterState.of(context).uri.toString() != route) context.push(route);
    return;
  }

  final target = Uri.tryParse(url);
  if (target == null) return;
  await launchUrl(target, mode: LaunchMode.externalApplication);
}
