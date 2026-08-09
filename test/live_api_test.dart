@Tags(['live'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:textlog/core/feed_source.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/data/api.dart';

/// Drives a local textlog against the write endpoints, through the same client the
/// app uses. Skipped unless a server is running.
///
///   cd ../textlog && bun run dev            # NODE_ENV=test, EMAIL_CAPTURE_PATH set
///   flutter test test/live_api_test.dart --dart-define=TEXTLOG_ORIGIN=http://localhost:3000
///
/// Sign in codes are limited to three an hour per address, so between runs:
///   delete from auth_rate_limits;
const mailbox = String.fromEnvironment(
  'TEXTLOG_MAIL',
  defaultValue: '/tmp/textlog-mail.jsonl',
);

String? latestCode() {
  final file = File(mailbox);
  if (!file.existsSync()) return null;
  String? code;
  for (final line in file.readAsLinesSync()) {
    if (line.trim().isEmpty) continue;
    final text = (jsonDecode(line) as Map<String, dynamic>)['text'] as String;
    final match = RegExp(r'Enter this code instead: (\d{6})').firstMatch(text);
    if (match != null) code = match.group(1);
  }
  return code;
}

/// Only ever runs against an origin you pointed it at yourself. Production answers
/// these reads perfectly well, and signing in and posting there is not what this is.
const isLocal = textlogOrigin != 'https://textlog.cc';

Future<bool> serverIsUp() async {
  if (!isLocal) return false;
  try {
    final response = await http
        .get(apiBase.resolve('feeds/latest'))
        .timeout(const Duration(seconds: 2));
    return response.statusCode == 200;
  } catch (_) {
    return false;
  }
}

void main() {
  late TextlogApi api;
  late http.Client client;

  setUpAll(() async {
    if (!await serverIsUp()) {
      markTestSkipped('no textlog at $textlogOrigin');
    }
  });

  setUp(() {
    client = http.Client();
    api = TextlogApi(client);
  });

  tearDown(() => client.close());

  test('signs in with an emailed code and posts natively', () async {
    if (!await serverIsUp()) return;

    await api.requestCode('dev@example.com');
    final code = latestCode();
    expect(code, isNotNull, reason: 'no code in $mailbox');

    final session = await api.verifyCode('dev@example.com', code!);
    expect(session.token, isNotEmpty);
    expect(session.account.handle, isNotEmpty);

    final account = await api.me(session.token);
    expect(account.writesEnabled, isTrue, reason: 'turn API access on for this account');

    final stamp = DateTime.now().microsecondsSinceEpoch;
    final post = await api.createPost(session.token, 'from the flutter client $stamp');
    expect(post.body, contains('$stamp'));

    final reply = await api.createPost(session.token, 'a reply $stamp', parentId: post.id);
    expect(reply.parentId, post.id);

    final edited = await api.editPost(session.token, post.id, 'edited $stamp');
    expect(edited.body, 'edited $stamp');

    // The reply is visible through the ordinary read endpoint.
    final replies = await api.feed(RepliesFeed(post.id));
    expect(replies.items.map((p) => p.id), contains(reply.id));

    await api.deletePost(session.token, reply.id);
  });

  test('refuses a bad code and an unknown token', () async {
    if (!await serverIsUp()) return;

    await expectLater(
      api.verifyCode('dev@example.com', '000000'),
      throwsA(isA<ApiFailure>()),
    );
    await expectLater(api.me('not-a-real-token'), throwsA(isA<ApiFailure>()));
  });
}
