import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/app_links.dart';

const _origin = 'https://textlog.cc';

String? route(String url, {String origin = _origin}) =>
    routeForUrl(url, origin: origin);

void main() {
  group('links the app can open itself', () {
    test('a post', () {
      expect(route('https://textlog.cc/post/2201'), '/post/2201');
      expect(route('http://textlog.cc/post/1'), '/post/1');
      // A query on a post link is the site's return path, which the app has no use for.
      expect(route('https://textlog.cc/post/12?from=%2Fhot'), '/post/12');
    });

    test('a profile, lower-cased as the app routes it', () {
      expect(route('https://textlog.cc/u/Stagas'), '/u/stagas');
    });

    test('a hashtag, and its followers', () {
      expect(route('https://textlog.cc/tag/ASCII'), '/tag/ascii');
      expect(route('https://textlog.cc/tag/ascii/followers'), '/tag/ascii/followers');
    });

    test('a unicode hashtag survives the round trip', () {
      expect(route('https://textlog.cc/tag/caf%C3%A9'), '/tag/caf%C3%A9');
    });

    test('the feeds the app mirrors', () {
      expect(route('https://textlog.cc/hot'), '/hot');
      expect(route('https://textlog.cc/latest'), '/latest');
      expect(route('https://textlog.cc/for-you'), '/for-you');
      expect(route('https://textlog.cc/to-me'), '/to-me');
      // The site's newer names for the same three feeds, which it now redirects the
      // old ones to. Both spellings open in the app.
      expect(route('https://textlog.cc/all'), '/latest');
      expect(route('https://textlog.cc/my-feed'), '/for-you');
      expect(route('https://textlog.cc/@'), '/to-me');
      expect(route('https://textlog.cc/bookmarks'), '/bookmarks');
      expect(route('https://textlog.cc/explore'), '/explore');
      expect(route('https://textlog.cc/drafts'), '/drafts');
    });

    test('the root', () {
      expect(route('https://textlog.cc'), '/');
      expect(route('https://textlog.cc/'), '/');
    });

    test('search keeps its query', () {
      expect(route('https://textlog.cc/search?q=ascii'), '/search?q=ascii');
      expect(route('https://textlog.cc/search'), '/search');
    });

    test("the site's sign-in becomes the app's", () {
      expect(route('https://textlog.cc/enter'), '/me');
    });
  });

  group('links that belong in a browser', () {
    test('another site', () {
      expect(route('https://github.com/stagas/textlog'), isNull);
      expect(route('https://example.com/post/1'), isNull);
    });

    test('a lookalike host', () {
      // Not this instance, whatever it calls itself.
      expect(route('https://textlog.cc.evil.example/post/1'), isNull);
      expect(route('https://nottextlog.cc/post/1'), isNull);
    });

    test('account settings, which are deliberately browser-only', () {
      expect(route('https://textlog.cc/account/edit'), isNull);
      expect(route('https://textlog.cc/account/security'), isNull);
    });

    test('anything the app has no screen for', () {
      expect(route('https://textlog.cc/about'), isNull);
      expect(route('https://textlog.cc/api'), isNull);
      expect(route('https://textlog.cc/post/not-a-number'), isNull);
      expect(route('https://textlog.cc/u/one/two/three'), isNull);
    });

    test('a scheme we would not follow', () {
      expect(route('javascript:alert(1)'), isNull);
      expect(route('mailto:someone@textlog.cc'), isNull);
    });

    test('nonsense', () {
      expect(route('not a url at all'), isNull);
      expect(route(''), isNull);
    });
  });

  test('a local instance is treated as its own', () {
    // So a build pointed at a development server does not send its own links away.
    expect(
      route('http://localhost:3000/post/7', origin: 'http://localhost:3000'),
      '/post/7',
    );
    expect(route('https://textlog.cc/post/7', origin: 'http://localhost:3000'), isNull);
  });
}
