import 'dart:convert';

import 'package:http/http.dart' as http;

import '../core/feed_source.dart';
import '../core/models.dart';

const textlogOrigin = 'https://textlog.cc';
final apiBase = Uri.parse('$textlogOrigin/api/v1/');

/// The only class in the app that performs I/O. Everything downstream of it is
/// pure, which is what makes the rest testable without a server.
final class TextlogApi {
  const TextlogApi(this._client);

  final http.Client _client;

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

  Future<Map<String, dynamic>> _get(String path, [Map<String, String>? query]) async {
    final response = await _client.get(
      apiBase.resolve(path).replace(queryParameters: query),
      headers: const {'accept': 'application/json'},
    );
    final body = jsonDecode(utf8.decode(response.bodyBytes)) as Map<String, dynamic>;

    if (response.statusCode >= 400) {
      final error = body['error'] as Map<String, dynamic>?;
      throw ApiFailure(
        code: error?['code'] as String? ?? 'unknown',
        message: error?['message'] as String? ?? 'Request failed',
        status: response.statusCode,
      );
    }
    return body;
  }
}
