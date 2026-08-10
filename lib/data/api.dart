import 'dart:convert';

import 'package:http/http.dart' as http;

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
  const TextlogApi(this._client, {this.onResult});

  final http.Client _client;

  /// Every answer, so one place can notice a 429.
  final void Function(ApiFailure? failure)? onResult;

  Future<Page<Post>> feed(FeedSource source, {String? cursor, int limit = 20}) async {
    final json = await _get(pathOf(source), {'limit': '$limit', 'cursor': ?cursor});
    return Page.fromJson(json, Post.fromJson);
  }

  Future<Post> post(int id) async {
    final json = await _get('posts/$id');
    return Post.fromJson(json['data'] as Map<String, dynamic>);
  }

  Future<Profile> profile(String handle) async {
    final json = await _get('users/${Uri.encodeComponent(handle)}');
    return Profile.fromJson(json['data'] as Map<String, dynamic>);
  }

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
