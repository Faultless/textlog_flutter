/// Filtering posts already on screen. No request goes out for this: it narrows the
/// list you have, which is what makes it instant.
library;

import 'models.dart';

/// Every space separated term must appear somewhere in the post: its body, its
/// author, or its tags. Terms are matched case-insensitively and as substrings, so
/// `stag mark` finds a post by @stagas about markdown.
bool postMatches(Post post, String query) {
  final terms = query.toLowerCase().split(RegExp(r'\s+')).where((term) => term.isNotEmpty);
  if (terms.isEmpty) return true;

  final haystack = [
    post.body,
    post.author.handle,
    ...post.tags,
    ...post.mentions,
  ].join('\n').toLowerCase();

  return terms.every(haystack.contains);
}

List<Post> searchPosts(List<Post> posts, String query) =>
    query.trim().isEmpty ? posts : posts.where((post) => postMatches(post, query)).toList();
