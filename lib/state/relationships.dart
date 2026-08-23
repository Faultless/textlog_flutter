import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/models.dart';
import '../data/api.dart';
import 'providers.dart';
import 'session.dart';

/// Who you follow and who you have blocked.
///
/// The API puts no `viewer_following` on a profile, so a follow button had nothing to
/// go on: it started out saying "follow" whether or not you already did. The
/// relationship endpoints close that hole — but only by listing, so this is a
/// *bounded* read, and the answer can be "I do not know".
///
/// That third answer matters. Guessing "not following" for somebody you followed two
/// years ago would make the button actively wrong; saying nothing and letting the tap
/// find out is worse than knowing but better than lying.
final class Relationships {
  const Relationships({
    required this.following,
    required this.blocked,
    this.followingComplete = false,
    this.blockedComplete = false,
    this.settled = const {},
  });

  final Set<String> following;
  final Set<String> blocked;

  /// Whether the list was walked to its end. When it was not, an account missing
  /// from the set is unknown rather than absent.
  final bool followingComplete;
  final bool blockedComplete;

  /// Accounts we acted on ourselves this session. An unfollow is knowledge even when
  /// the list walk stopped short, so it must not fall back to "I do not know".
  final Set<String> settled;

  static const unknown = Relationships(following: {}, blocked: {});

  bool? follows(String handle) => following.contains(handle)
      ? true
      : (followingComplete || settled.contains(handle) ? false : null);

  bool? blocks(String handle) => blocked.contains(handle)
      ? true
      : (blockedComplete || settled.contains(handle) ? false : null);


  Relationships copyWith({
    Set<String>? following,
    Set<String>? blocked,
    bool? followingComplete,
    bool? blockedComplete,
    Set<String>? settled,
  }) => Relationships(
    following: following ?? this.following,
    blocked: blocked ?? this.blocked,
    followingComplete: followingComplete ?? this.followingComplete,
    blockedComplete: blockedComplete ?? this.blockedComplete,
    settled: settled ?? this.settled,
  );
}

/// Loaded lazily — nothing asks until a follow or block control is on screen — and
/// capped, because this is a list walk and the rate limit is shared with reading.
///
/// Five pages of a hundred covers all but the heaviest accounts in at most five
/// requests, once per session.
const maxRelationshipPages = 5;

final relationshipsProvider =
    AsyncNotifierProvider<RelationshipsNotifier, Relationships>(RelationshipsNotifier.new);

class RelationshipsNotifier extends AsyncNotifier<Relationships> {
  @override
  Future<Relationships> build() async {
    // Awaited, not read: a session still loading is not the same as no session, and
    // answering "not following" on the strength of that would be a wrong answer.
    final session = await ref.watch(sessionProvider.future);
    if (session == null) return Relationships.unknown;

    final api = ref.watch(apiProvider);
    final handle = session.account.handle;

    // Each list is walked on its own. Failing to load one must not blank the other:
    // a blocks endpoint that errors should not make the follow buttons forget who you
    // follow. "I do not know" is a safe answer, but only for the list that failed.
    final following = await _walk(
      (cursor) => api.people(handle, PeopleKind.following, cursor: cursor, limit: 100),
    );
    final blocked = await _walk(
      (cursor) => api.people(
        handle,
        PeopleKind.blocks,
        cursor: cursor,
        limit: 100,
        token: session.token,
      ),
    );
    return Relationships(
      following: following.handles,
      blocked: blocked.handles,
      followingComplete: following.complete,
      blockedComplete: blocked.complete,
    );
  }

  Future<({Set<String> handles, bool complete})> _walk(
    Future<Page<UserRef>> Function(String? cursor) fetch,
  ) async {
    final handles = <String>{};
    String? cursor;
    try {
      for (var page = 0; page < maxRelationshipPages; page++) {
        final result = await fetch(cursor);
        handles.addAll(result.items.map((person) => person.handle));
        cursor = result.nextCursor;
        if (cursor == null) return (handles: handles, complete: true);
      }
    } catch (_) {
      // Whatever arrived is still true; it is just not the whole list.
      return (handles: handles, complete: false);
    }
    return (handles: handles, complete: false);
  }

  /// Record a change we just made, so every control showing that account agrees
  /// without anybody refetching a list.
  void noteFollow(String handle, {required bool following}) {
    final current = state.valueOrNull ?? Relationships.unknown;
    state = AsyncData(
      current.copyWith(
        following: following
            ? {...current.following, handle}
            : ({...current.following}..remove(handle)),
        settled: {...current.settled, handle},
      ),
    );
  }

  void noteBlock(String handle, {required bool blocked}) {
    final current = state.valueOrNull ?? Relationships.unknown;
    state = AsyncData(
      current.copyWith(
        blocked: blocked ? {...current.blocked, handle} : ({...current.blocked}..remove(handle)),
        // Blocking on textlog drops the follow with it.
        following: blocked ? ({...current.following}..remove(handle)) : current.following,
        settled: {...current.settled, handle},
      ),
    );
  }
}

/// Whether you follow [handle] — null while that is genuinely unknown.
final followsProvider = Provider.autoDispose.family<bool?, String>(
  (ref, handle) => ref.watch(relationshipsProvider).valueOrNull?.follows(handle),
);

final blocksProvider = Provider.autoDispose.family<bool?, String>(
  (ref, handle) => ref.watch(relationshipsProvider).valueOrNull?.blocks(handle),
);

/// The hashtags you follow.
///
/// Its own notifier rather than part of [Relationships], because only a hashtag screen
/// ever asks — and folding it in would have made every follow button on a profile pay
/// for a list it has no use for.
final followedTagSetProvider =
    AsyncNotifierProvider<FollowedTagSetNotifier, ({Set<String> tags, bool complete})>(
      FollowedTagSetNotifier.new,
    );

class FollowedTagSetNotifier
    extends AsyncNotifier<({Set<String> tags, bool complete})> {
  @override
  Future<({Set<String> tags, bool complete})> build() async {
    final session = await ref.watch(sessionProvider.future);
    if (session == null) return (tags: <String>{}, complete: false);

    final tags = <String>{};
    String? cursor;
    try {
      for (var page = 0; page < maxRelationshipPages; page++) {
        final result = await ref
            .read(apiProvider)
            .followedTags(session.account.handle, cursor: cursor, limit: 100);
        tags.addAll(result.items.map((tag) => tag.tag));
        cursor = result.nextCursor;
        if (cursor == null) return (tags: tags, complete: true);
      }
    } catch (_) {
      return (tags: tags, complete: false);
    }
    return (tags: tags, complete: false);
  }

  void note(String tag, {required bool following}) {
    final current = state.valueOrNull ?? (tags: <String>{}, complete: false);
    state = AsyncData((
      tags: following ? {...current.tags, tag} : ({...current.tags}..remove(tag)),
      // Acting on it is knowledge, so the set is authoritative for this tag either way.
      complete: current.complete,
    ));
    _settled.add(tag);
  }

  final _settled = <String>{};

  bool? follows(String tag) {
    final current = state.valueOrNull;
    if (current == null) return null;
    if (current.tags.contains(tag)) return true;
    return current.complete || _settled.contains(tag) ? false : null;
  }
}

/// Whether you follow a hashtag — null while that is genuinely unknown.
final followsTagProvider = Provider.autoDispose.family<bool?, String>((ref, tag) {
  ref.watch(followedTagSetProvider);
  return ref.read(followedTagSetProvider.notifier).follows(tag);
});
