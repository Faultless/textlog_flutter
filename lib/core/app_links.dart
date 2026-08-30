/// Which of textlog's own URLs the app can open itself.
///
/// A link to textlog.cc used to leave the app: tapping `/post/2201` in a body opened a
/// browser on a page the reader was already inside an app for. Anything the app has a
/// screen for is handled here; everything else still goes to the browser, because that
/// is where it belongs — account settings and signing up are deliberately not in here.
///
/// Pure, so the whole table is testable without a router.
library;

/// The in-app route for [url], or null when the app has no screen for it.
///
/// [origin] is the instance the app is pointed at, so a build aimed at a local textlog
/// treats that host as its own rather than sending it to a browser.
String? routeForUrl(String url, {required String origin}) {
  final target = Uri.tryParse(url);
  final home = Uri.tryParse(origin);
  if (target == null || home == null) return null;

  // Only this instance. A link to some other textlog is somebody else's site.
  if (target.host.isEmpty || target.host.toLowerCase() != home.host.toLowerCase()) {
    return null;
  }
  // A scheme we would not follow anyway.
  if (target.scheme.isNotEmpty && target.scheme != 'http' && target.scheme != 'https') {
    return null;
  }

  final segments = [
    for (final segment in target.pathSegments)
      if (segment.isNotEmpty) segment,
  ];
  if (segments.isEmpty) return '/';

  return switch (segments) {
    ['post', final id] when int.tryParse(id) != null => '/post/$id',
    ['u', final handle] => '/u/${Uri.encodeComponent(handle.toLowerCase())}',
    ['tag', final tag] => '/tag/${Uri.encodeComponent(tag.toLowerCase())}',
    ['tag', final tag, 'followers'] =>
      '/tag/${Uri.encodeComponent(tag.toLowerCase())}/followers',
    // The site's own names for the feeds, which the app mirrors. It renamed three
    // of them — `/latest` is `/all`, `/for-you` is `/my-feed`, `/to-me` is `/@` —
    // and redirects the old ones, so both spellings are in here: a link written a
    // year ago should still open in the app rather than bouncing to a browser.
    ['hot'] => '/hot',
    ['all'] || ['latest'] => '/latest',
    ['my-feed'] || ['for-you'] => '/for-you',
    ['@'] || ['to-me'] => '/to-me',
    ['explore'] => '/explore',
    ['drafts'] => '/drafts',
    ['bookmarks'] => '/bookmarks',
    ['search'] => target.query.isEmpty ? '/search' : '/search?${target.query}',
    // `/enter` is the site's sign-in page; the app has its own.
    ['enter'] => '/me',
    // Anything else — /account, /about, signing up — is the browser's.
    _ => null,
  };
}
