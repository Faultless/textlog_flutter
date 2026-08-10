import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:textlog/state/cache.dart';
import 'package:textlog/state/providers.dart';
import 'package:textlog/state/thread.dart';

Map<String, dynamic> post(int id, {required int parent, int replyCount = 0}) => {
  'id': id,
  'body': 'post $id',
  'created_at': '2026-08-08T08:00:00.000Z',
  'parent_id': parent,
  'reply_count': replyCount,
  'tags': <String>[],
  'mentions': <String>[],
  'url': 'https://textlog.cc/post/$id',
  'api_url': 'https://textlog.cc/api/v1/posts/$id',
  'author': {
    'handle': 'a',
    'url': 'https://textlog.cc/u/a',
    'api_url': 'https://textlog.cc/api/v1/users/a',
  },
};

/// A chain: 1 -> 2 -> 3 -> ... each with exactly one reply, forever.
ProviderContainer chainContainer(List<String> requested) {
  final container = ProviderContainer(
    overrides: [
      httpClientProvider.overrideWithValue(
        MockClient((request) async {
          final id = int.parse(RegExp(r'/posts/(\d+)/replies').firstMatch(request.url.path)![1]!);
          requested.add('$id');
          return http.Response(
            jsonEncode({
              'data': [post(id + 1, parent: id, replyCount: 1)],
              'pagination': {'next_cursor': null},
            }),
            200,
          );
        }),
      ),
    ],
  );
  addTearDown(container.dispose);
  return container;
}

void main() {
  test('opening a thread asks for one level, whatever is below it', () async {
    final requested = <String>[];
    final tree = await chainContainer(requested).read(threadProvider(1).future);

    expect(requested, ['1']);
    expect(tree.single.children, isEmpty);
    expect(tree.single.unloaded, 1, reason: 'what was not loaded is still advertised');
  });

  test('expanding a branch costs one request', () async {
    final requested = <String>[];
    final container = chainContainer(requested);
    await container.read(threadProvider(1).future);

    await container.read(threadProvider(1).notifier).expand(2);

    expect(requested, ['1', '2']);
    expect(container.read(threadProvider(1)).value!.single.children.single.post.id, 3);
  });

  test('expanding never walks past the depth cap', () async {
    final requested = <String>[];
    final container = chainContainer(requested);
    await container.read(threadProvider(1).future);

    for (var id = 2; id <= 9; id++) {
      await container.read(threadProvider(1).notifier).expand(id);
    }

    expect(requested.length, maxThreadDepth);
    var node = container.read(threadProvider(1)).value!.single;
    var depth = 1;
    while (node.children.isNotEmpty) {
      node = node.children.single;
      depth++;
    }
    expect(depth, maxThreadDepth);
    expect(node.hasUnloaded, isTrue);
  });

  test('a level is fetched a few at a time', () async {
    var inFlight = 0;
    var peak = 0;
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            final id = int.parse(
              RegExp(r'/posts/(\d+)/replies').firstMatch(request.url.path)![1]!,
            );
            inFlight++;
            peak = inFlight > peak ? inFlight : peak;
            await Future<void>.delayed(const Duration(milliseconds: 5));
            inFlight--;
            final children = id == 1
                ? [for (var i = 2; i <= 5; i++) post(i, parent: 1, replyCount: 1)]
                : [post(id * 10, parent: id)];
            return http.Response(
              jsonEncode({'data': children, 'pagination': {'next_cursor': null}}),
              200,
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    await container.read(threadProvider(1).future);
    for (var id = 2; id <= 5; id++) {
      await container.read(threadProvider(1).notifier).expand(id);
    }
    await container.read(threadProvider(1).notifier).refresh();

    expect(peak, lessThanOrEqualTo(maxThreadConcurrency));
  });

  test('a wide level is fetched in one batch, within budget', () async {
    final requested = <String>[];
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient((request) async {
            final id = int.parse(
              RegExp(r'/posts/(\d+)/replies').firstMatch(request.url.path)![1]!,
            );
            requested.add('$id');
            // The root has 40 children, each claiming a reply of its own.
            final children = id == 1
                ? [for (var i = 2; i <= 41; i++) post(i, parent: 1, replyCount: 1)]
                : <Map<String, dynamic>>[];
            return http.Response(
              jsonEncode({
                'data': children,
                'pagination': {'next_cursor': null},
              }),
              200,
            );
          }),
        ),
      ],
    );
    addTearDown(container.dispose);

    final tree = await container.read(threadProvider(1).future);

    expect(tree.length, 40);
    expect(
      requested.length,
      lessThanOrEqualTo(maxThreadRequests),
      reason: 'the budget is a hard ceiling',
    );
    // Whatever the budget could not reach is still advertised, not silently dropped.
    expect(tree.where((n) => n.hasUnloaded), isNotEmpty);
  });

  test('a thread with no replies is an empty tree', () async {
    final container = ProviderContainer(
      overrides: [
        httpClientProvider.overrideWithValue(
          MockClient(
            (_) async => http.Response(
              jsonEncode({
                'data': [],
                'pagination': {'next_cursor': null},
              }),
              200,
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    expect(await container.read(threadProvider(1).future), isEmpty);
  });

  test('loaded replies land in the shared post cache', () async {
    final container = chainContainer([]);
    await container.read(threadProvider(1).future);
    expect(container.read(postCacheProvider)[2], isNotNull);
  });
}
