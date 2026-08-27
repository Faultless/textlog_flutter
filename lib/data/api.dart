import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/body_tokens.dart' show linkOrigin;
import '../core/feed_source.dart';
import '../core/models.dart';

/// Point the app at a local server with
/// `--dart-define=TEXTLOG_ORIGIN=http://localhost:3000`.
const textlogOrigin = String.fromEnvironment(
  'TEXTLOG_ORIGIN',
  defaultValue: 'https://textlog.cc',
);
final apiBase = Uri.parse('$textlogOrigin/api/v1/');

/// The only class in the app that performs I/O. Everything downstream of it is
/// pure, which is what makes the rest testable without a server.
final class TextlogApi {
  TextlogApi(this._client, {this.onResult}) {
    // So a link back to this instance renders as a path rather than a full URL,
    // the way the site labels its own links.
    linkOrigin = textlogOrigin;
  }

  final http.Client _client;

  /// Every answer, so one place can notice a 429.
  final void Function(ApiFailure? failure)? onResult;

  // -- reads -----------------------------------------------------------------

  /// A feed, read as [token]'s owner when one is given.
  ///
  /// The token is optional to the server but it changes the answer, and not only by
  /// adding unread state: an anonymous read applies no viewer, so the accounts and
  /// hashtags *you* blocked come back in it. Reading as yourself is also counted
  /// against the higher authenticated rate limit rather than the shared anonymous one.
  Future<Page<Post>> feed(
    FeedSource source, {
    String? cursor,
    int limit = 20,
    String? token,
  }) async => Page.fromJson(
    await feedJson(source, cursor: cursor, limit: limit, token: token),
    Post.fromJson,
  );

  /// The same read, undecoded.
  ///
  /// The body is what gets kept for a cold start: storing the server's own JSON and
  /// parsing it back with [Page.fromJson] means the stored copy round-trips exactly,
  /// and there is no second serialiser to keep in step with the model.
  Future<Map<String, dynamic>> feedJson(
    FeedSource source, {
    String? cursor,
    int limit = 20,
    String? token,
  }) => _send(
    'GET',
    pathOf(source),
    token: token,
    query: {'limit': '$limit', 'cursor': ?cursor, ...queryOf(source)},
  );

  Future<Post> post(int id) async {
    final json = await _get('posts/$id');
    return Post.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<Profile> profile(String handle, {String? token}) async {
    final json = await _send('GET', 'users/${Uri.encodeComponent(handle)}', token: token);
    return Profile.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<TagDetails> tag(String tag) async {
    final json = await _get('tags/${Uri.encodeComponent(tag)}');
    return TagDetails.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Who follows whom. [kind] is one of the relationship paths below.
  Future<Page<UserRef>> people(
    String handle,
    PeopleKind kind, {
    String? cursor,
    int limit = 50,
    String? token,
  }) async {
    final json = await _send(
      'GET',
      'users/${Uri.encodeComponent(handle)}/${kind.path}',
      query: {'limit': '$limit', 'cursor': ?cursor},
      // Only `blocks` needs it, but sending it never hurts and it keeps the
      // caller from having to know which one is private.
      token: token,
    );
    return Page.fromJson(json, UserRef.fromJson);
  }

  Future<Page<UserRef>> tagFollowers(String tag, {String? cursor, int limit = 50}) async {
    final json = await _get('tags/${Uri.encodeComponent(tag)}/followers', {
      'limit': '$limit',
      'cursor': ?cursor,
    });
    return Page.fromJson(json, UserRef.fromJson);
  }

  Future<Page<TagDetails>> followedTags(
    String handle, {
    String? cursor,
    int limit = 50,
  }) async {
    final json = await _get('users/${Uri.encodeComponent(handle)}/following/tags', {
      'limit': '$limit',
      'cursor': ?cursor,
    });
    return Page.fromJson(json, TagDetails.fromJson);
  }

  /// `/activities/for-you` or `/activities/to-me`. Both need a token.
  Future<Page<Activity>> activities(
    String token,
    ActivityScope scope, {
    String? cursor,
    int limit = 20,
  }) async {
    final json = await _send(
      'GET',
      'activities/${scope.path}',
      query: {'limit': '$limit', 'cursor': ?cursor},
      token: token,
    );
    return Page.fromJson(json, Activity.fromJson);
  }

  /// Mark specific rows read. The server takes 1–100 ids at a time.
  Future<void> markRead(String token, ActivityScope scope, List<String> ids) =>
      _send('POST', 'activities/${scope.path}/read', token: token, body: {
        'activity_ids': ids,
      });

  Future<void> markAllRead(String token, ActivityScope scope) =>
      _send('POST', 'activities/${scope.path}/read-all', token: token);

  // -- auth and account ------------------------------------------------------

  /// Ask the server to email a sign-in code. Answers the same whether or not the
  /// address has an account.
  Future<void> requestCode(String email) =>
      _send('POST', 'auth/request', body: {'email': email});

  Future<Session> verifyCode(String email, String code) async {
    final json = await _send('POST', 'auth/verify', body: {'email': email, 'code': code});
    return Session.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<void> signOut(String token) => _send('DELETE', 'auth/session', token: token);

  Future<Account> me(String token) async {
    final json = await _send('GET', 'me', token: token);
    return Account.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<Account> editBio(String token, String bio) async {
    final json = await _send('PATCH', 'me', token: token, body: {'bio': bio});
    return Account.fromJson(json['data'] as Map<String, dynamic>);
  }

  // -- writes ----------------------------------------------------------------

  Future<Post> createPost(String token, String body, {int? parentId}) async {
    final json = await _send('POST', 'posts', token: token, body: {
      'body': body,
      'parent_id': ?parentId,
    });
    return Post.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<Post> editPost(String token, int id, String body) async {
    final json = await _send('PATCH', 'posts/$id', token: token, body: {'body': body});
    return Post.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<void> deletePost(String token, int id) => _send('DELETE', 'posts/$id', token: token);

  /// Take a published post back to drafts, returning the draft it became.
  ///
  /// The website has had this as a form action for a while; it is an API route now,
  /// which is what let the app offer it. Not the same as deleting: the words survive,
  /// they are just no longer published.
  Future<Draft> unpublishPost(String token, int id) async {
    final json = await _send('POST', 'posts/$id/unpublish', token: token);
    return Draft.fromJson(json['data'] as Map<String, dynamic>);
  }

  /// Mark specific posts in the latest feed as read.
  ///
  /// Capped at 100 an request by the server, so the caller chunks.
  Future<void> markLatestRead(String token, List<int> postIds) => _send(
    'POST',
    'feeds/latest/read',
    token: token,
    body: {'post_ids': postIds},
  );

  Future<void> markLatestReadAll(String token) =>
      _send('POST', 'feeds/latest/read-all', token: token);

  Future<void> follow(String token, String handle, {required bool following}) => _send(
    following ? 'POST' : 'DELETE',
    'users/${Uri.encodeComponent(handle)}/follow',
    token: token,
  );

  Future<void> block(String token, String handle, {required bool blocked}) => _send(
    blocked ? 'POST' : 'DELETE',
    'users/${Uri.encodeComponent(handle)}/block',
    token: token,
  );

  Future<void> report(String token, int id, String reason) =>
      _send('POST', 'posts/$id/report', token: token, body: {'reason': reason});

  /// Cast a vote. Answers with the post, so the tally the server now reveals can go
  /// straight on screen without a second read.
  Future<Post> votePoll(String token, int postId, int optionId) async {
    final json = await _send(
      'POST',
      'posts/$postId/poll/votes',
      token: token,
      body: {'option_id': optionId},
    );
    return Post.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<void> followTag(String token, String tag, {required bool following}) => _send(
    following ? 'POST' : 'DELETE',
    'tags/${Uri.encodeComponent(tag)}/follow',
    token: token,
  );

  Future<void> blockTag(String token, String tag, {required bool blocked}) => _send(
    blocked ? 'POST' : 'DELETE',
    'tags/${Uri.encodeComponent(tag)}/block',
    token: token,
  );

  // -- drafts ----------------------------------------------------------------

  Future<Page<Draft>> drafts(String token, {String? cursor, int limit = 20}) async {
    final json = await _send(
      'GET',
      'drafts',
      query: {'limit': '$limit', 'cursor': ?cursor},
      token: token,
    );
    return Page.fromJson(json, Draft.fromJson);
  }

  Future<Draft> saveDraft(String token, String body, {int? parentId}) async {
    final json = await _send('POST', 'drafts', token: token, body: {
      'body': body,
      'parent_id': parentId,
    });
    return Draft.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<Draft> editDraft(String token, int id, String body) async {
    final json = await _send('PATCH', 'drafts/$id', token: token, body: {'body': body});
    return Draft.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<void> deleteDraft(String token, int id) =>
      _send('DELETE', 'drafts/$id', token: token);

  /// Post it. The draft is gone afterwards, and the answer is the post it became.
  Future<Post> publishDraft(String token, int id) async {
    final json = await _send('POST', 'drafts/$id/publish', token: token);
    return Post.fromJson(json['data'] as Map<String, dynamic>);
  }

  // -- discovery -------------------------------------------------------------

  /// People and hashtags worth following, in one request. Both lists page on their
  /// own cursors, which is why this is not a [Page].
  Future<Explore> explore({
    String? token,
    String? peopleCursor,
    String? tagsCursor,
    int limit = 20,
  }) async {
    final json = await _send('GET', 'explore', token: token, query: {
      'people_limit': '$limit',
      'tags_limit': '$limit',
      'people_cursor': ?peopleCursor,
      'tags_cursor': ?tagsCursor,
    });
    return Explore.fromJson(json);
  }

  // -- plumbing --------------------------------------------------------------

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) =>
      _send('GET', path, query: query);

  Future<Map<String, dynamic>> _send(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    String? token,
  }) async {
    final request = http.Request(
      method,
      apiBase.resolve(path).replace(queryParameters: query),
    );
    request.headers['accept'] = 'application/json';
    if (token != null) request.headers['authorization'] = 'Bearer $token';
    if (body != null) {
      request.headers['content-type'] = 'application/json';
      request.body = jsonEncode(body);
    }

    // Nothing may hang forever.
    final streamed = await _client.send(request).timeout(requestTimeout);
    final response = await http.Response.fromStream(streamed).timeout(requestTimeout);
    final decoded = _decode(response);

    if (response.statusCode >= 400) {
      final error = decoded['error'] as Map<String, dynamic>?;
      final failure = ApiFailure(
        code: error?['code'] as String? ?? 'unknown',
        message: error?['message'] as String? ?? 'Request failed',
        status: response.statusCode,
        retryAfter: retryAfterOf(response.headers),
      );
      onResult?.call(failure);
      throw failure;
    }
    onResult?.call(null);
    return decoded;
  }
}

/// The relationship lists a profile can show.
enum PeopleKind {
  followers('followers'),
  following('following/users'),
  blocks('blocks');

  const PeopleKind(this.path);
  final String path;
}

/// The two activity feeds. `forYou` is everything from accounts and tags you follow;
/// `toMe` is the subset aimed at you — replies and mentions.
enum ActivityScope {
  forYou('for-you'),
  toMe('to-me');

  const ActivityScope(this.path);
  final String path;
}

/// Long enough for a bad connection, short enough to fail rather than hang.
const requestTimeout = Duration(seconds: 20);

/// A proxy can answer in HTML. Anything unparseable counts as no body.
Map<String, dynamic> _decode(http.Response response) {
  if (response.body.isEmpty) return const {};
  try {
    final decoded = jsonDecode(utf8.decode(response.bodyBytes));
    return decoded is Map<String, dynamic> ? decoded : const {};
  } catch (_) {
    return const {};
  }
}

/// Seconds only. The HTTP-date form would need dart:io, which web lacks.
Duration? retryAfterOf(Map<String, String> headers) {
  final seconds = int.tryParse(headers['retry-after']?.trim() ?? '');
  if (seconds == null || seconds < 0) return null;
  return Duration(seconds: seconds);
}
