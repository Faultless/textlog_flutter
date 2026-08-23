import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import 'cache.dart';
import 'providers.dart';
import 'session.dart';

/// Drafts, kept on the server rather than on the device.
///
/// That is the whole point of them being an endpoint: a draft started on a phone is
/// there on the website, and the app does not have to become a second place your
/// half-written posts can be lost.
final draftsProvider = AsyncNotifierProvider<DraftsNotifier, List<Draft>>(
  DraftsNotifier.new,
);

/// How many drafts you have, for the compose sheet's link into them.
final draftCountProvider = Provider<int>(
  (ref) => ref.watch(draftsProvider).valueOrNull?.length ?? 0,
);

class DraftsNotifier extends AsyncNotifier<List<Draft>> {
  @override
  Future<List<Draft>> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session == null) return const [];
    final page = await ref.read(apiProvider).drafts(session.token, limit: 100);
    _remember(page.items);
    return page.items;
  }

  /// A draft carries the post it replies to, so keeping those means opening one
  /// shows its context without a fetch.
  void _remember(List<Draft> drafts) {
    final parents = [for (final draft in drafts) ?draft.parent];
    if (parents.isNotEmpty) ref.read(postCacheProvider).remember(parents);
  }

  Future<Draft?> save(String body, {int? parentId}) async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null) return null;
    final draft = await ref.read(apiProvider).saveDraft(session.token, body, parentId: parentId);
    // Newest first, as the list reads.
    state = AsyncData([draft, ...state.valueOrNull ?? const []]);
    return draft;
  }

  Future<Draft?> edit(int id, String body) async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null) return null;
    final draft = await ref.read(apiProvider).editDraft(session.token, id, body);
    _replace(id, draft);
    return draft;
  }

  Future<void> discard(int id) async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null) return;
    // Off the list first: the server has to agree, but a row that lingers after you
    // deleted it reads as the tap not having worked.
    final before = state.valueOrNull ?? const <Draft>[];
    _replace(id, null);
    try {
      await ref.read(apiProvider).deleteDraft(session.token, id);
    } catch (_) {
      state = AsyncData(before);
      rethrow;
    }
  }

  /// Post it. The draft is consumed, so it leaves the list either way.
  Future<Post?> publish(int id) async {
    final session = ref.read(sessionProvider).valueOrNull;
    if (session == null) return null;
    final post = await ref.read(apiProvider).publishDraft(session.token, id);
    _replace(id, null);

    ref.read(postCacheProvider).remember([post]);
    // A reply changes its parent's thread; a note belongs at the top of latest.
    if (post.parentId case final parentId?) {
      ref.read(postCacheProvider).forget(parentId);
      ref.read(repliesCacheProvider).forget(parentId);
      ref.invalidate(postProvider(parentId));
    }
    ref.invalidate(profileProvider(post.author.handle));
    return post;
  }

  void _replace(int id, Draft? draft) {
    final current = state.valueOrNull;
    if (current == null) return;
    state = AsyncData([
      for (final existing in current)
        if (existing.id != id) existing else ?draft,
    ]);
  }

  Future<void> refresh() async {
    ref.invalidateSelf();
    await future;
  }
}
