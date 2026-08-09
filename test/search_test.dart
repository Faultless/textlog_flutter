import 'package:flutter_test/flutter_test.dart';
import 'package:textlog/core/models.dart';
import 'package:textlog/core/search.dart';

Post post(int id, String body, {String handle = 'alice', List<String> tags = const []}) => Post(
  id: id,
  body: body,
  createdAt: DateTime(2026, 8, 9),
  parentId: null,
  replyCount: 0,
  tags: tags,
  mentions: const [],
  url: Uri.parse('https://textlog.cc/post/$id'),
  author: Author(handle: handle, url: Uri.parse('https://textlog.cc/u/$handle')),
);

void main() {
  final posts = [
    post(1, 'building small tools', handle: 'stagas', tags: ['build']),
    post(2, 'Markdown would be good', handle: 'fastidious'),
    post(3, 'a quiet walk', handle: 'alice', tags: ['city']),
  ];

  test('an empty query keeps everything', () {
    expect(searchPosts(posts, '   ').length, 3);
  });

  test('matches body, handle and tag, case-insensitively', () {
    expect(searchPosts(posts, 'MARKDOWN').single.id, 2);
    expect(searchPosts(posts, 'stagas').single.id, 1);
    expect(searchPosts(posts, 'city').single.id, 3);
  });

  test('every term has to match, across fields', () {
    // handle from one field, body from another.
    expect(searchPosts(posts, 'stag tools').single.id, 1);
    expect(searchPosts(posts, 'stag walk'), isEmpty);
  });

  test('matches on substrings, so partial words find things', () {
    expect(searchPosts(posts, 'mark').single.id, 2);
  });
}
