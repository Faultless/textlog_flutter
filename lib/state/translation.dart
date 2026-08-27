import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Posts the reader asked to see translated, by id.
///
/// Kept for the session rather than in the widget, so a post stays translated while
/// you scroll away and back, and so a post you translated in a feed is still
/// translated when you open its thread. Not persisted: it is a per-reading choice,
/// not a preference — the preference is whether the button appears at all.
final translatedPostsProvider =
    NotifierProvider<TranslatedPosts, Set<int>>(TranslatedPosts.new);

class TranslatedPosts extends Notifier<Set<int>> {
  @override
  Set<int> build() => const {};

  void toggle(int postId) {
    final next = {...state};
    if (!next.remove(postId)) next.add(postId);
    state = next;
  }
}
