/// Immutable mirrors of the shapes documented at https://textlog.cc/api/openapi.json
library;

final class Author {
  const Author({required this.handle, required this.url});

  final String handle;
  final Uri url;

  /// The server hands out `deleted-<id>` for an account that has been removed. The
  /// site renders those as `(deleted account)` rather than a link to nothing.
  bool get isDeleted => isDeletedHandle(handle);

  factory Author.fromJson(Map<String, dynamic> json) => Author(
    handle: (json['handle'] as String).toLowerCase(),
    url: Uri.parse(json['url'] as String),
  );
}

final _deletedHandle = RegExp(r'^deleted-\d+$');

/// The server hands out `deleted-<id>` once an account is removed. Nothing links to
/// one, and the site prints `(deleted account)` where the handle would go.
bool isDeletedHandle(String handle) => _deletedHandle.hasMatch(handle);

final class Post {
  const Post({
    required this.id,
    required this.body,
    required this.createdAt,
    required this.parentId,
    required this.replyCount,
    required this.tags,
    required this.mentions,
    required this.url,
    required this.author,
    this.topId,
    this.parent,
    this.depth,
  });

  final int id;

  /// The top-level post of this thread, or null when this post *is* top-level.
  /// Drives the quoted parent's "top" link straight to the root of a conversation.
  final int? topId;

  final String body;
  final DateTime createdAt;
  final int? parentId;
  final int replyCount;
  final List<String> tags;
  final List<String> mentions;
  final Uri url;
  final Author author;

  /// The quoted parent, inlined by the server on every post-bearing response.
  ///
  /// This is what removes a request per reply on screen. The nested copy carries no
  /// `parent` of its own, so a quote never quotes a quote.
  final Post? parent;

  /// Distance from the post whose replies were requested. Only set on
  /// `/posts/{id}/replies`, which is the one endpoint that returns a whole subtree.
  final int? depth;

  bool get isReply => parentId != null;

  /// True when the author replied to themselves — the site says "continued" rather
  /// than "replied" for that.
  bool get isContinuation => parent != null && parent!.author.handle == author.handle;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['id'] as int,
    topId: json['top_id'] as int?,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    parentId: json['parent_id'] as int?,
    replyCount: json['reply_count'] as int,
    tags: List<String>.from(json['tags'] as List),
    mentions: List<String>.from(json['mentions'] as List),
    url: Uri.parse(json['url'] as String),
    author: Author.fromJson(json['author'] as Map<String, dynamic>),
    parent: switch (json['parent']) {
      final Map<String, dynamic> parent => Post.fromJson(parent),
      _ => null,
    },
    depth: json['depth'] as int?,
  );

  Post copyWith({String? body, int? replyCount, Post? parent}) => Post(
    id: id,
    topId: topId,
    body: body ?? this.body,
    createdAt: createdAt,
    parentId: parentId,
    replyCount: replyCount ?? this.replyCount,
    tags: tags,
    mentions: mentions,
    url: url,
    author: author,
    parent: parent ?? this.parent,
    depth: depth,
  );

  @override
  bool operator ==(Object other) => other is Post && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

final class Profile {
  const Profile({
    required this.handle,
    required this.bio,
    required this.createdAt,
    required this.postCount,
    required this.repliesCount,
    required this.followerCount,
    required this.followingUserCount,
    required this.followingTagCount,
    required this.url,
    this.blockedUserCount,
    this.blockedTagCount,
  });

  final String handle;
  final String bio;
  final DateTime createdAt;

  /// Top-level posts only. `repliesCount` is the rest.
  final int postCount;
  final int repliesCount;
  final int followerCount;
  final int followingUserCount;
  final int followingTagCount;
  final Uri url;

  /// Only present when you ask for your own profile with a token.
  final int? blockedUserCount;
  final int? blockedTagCount;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    handle: (json['handle'] as String).toLowerCase(),
    bio: json['bio'] as String? ?? '',
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    postCount: json['post_count'] as int? ?? 0,
    repliesCount: json['replies_count'] as int? ?? 0,
    followerCount: json['follower_count'] as int? ?? 0,
    // `following_count` is the older alias, kept for a server that predates the split.
    followingUserCount:
        json['following_user_count'] as int? ?? json['following_count'] as int? ?? 0,
    followingTagCount: json['following_tag_count'] as int? ?? 0,
    url: Uri.parse(json['url'] as String),
    blockedUserCount: json['blocked_user_count'] as int?,
    blockedTagCount: json['blocked_tag_count'] as int?,
  );
}

/// A hashtag with its counts, from `/tags/{tag}`.
final class TagDetails {
  const TagDetails({
    required this.tag,
    required this.postCount,
    required this.followerCount,
  });

  final String tag;
  final int postCount;
  final int followerCount;

  factory TagDetails.fromJson(Map<String, dynamic> json) => TagDetails(
    tag: json['tag'] as String,
    postCount: json['post_count'] as int? ?? 0,
    followerCount: json['follower_count'] as int? ?? 0,
  );
}

/// A bare `{handle, url}` — what the relationship endpoints return.
final class UserRef {
  const UserRef({required this.handle, required this.url});

  final String handle;
  final Uri url;

  factory UserRef.fromJson(Map<String, dynamic> json) => UserRef(
    handle: (json['handle'] as String).toLowerCase(),
    url: Uri.parse(json['url'] as String),
  );
}

/// What the activity feeds can carry.
enum ActivityKind {
  post,
  reply,
  mention,
  userFollow,
  tagFollow,
  signup,
  unknown;

  static ActivityKind fromJson(String? value) => switch (value) {
    'post' => ActivityKind.post,
    'reply' => ActivityKind.reply,
    'mention' => ActivityKind.mention,
    'user_follow' => ActivityKind.userFollow,
    'tag_follow' => ActivityKind.tagFollow,
    'signup' => ActivityKind.signup,
    _ => ActivityKind.unknown,
  };
}

/// One row of `/activities/for-you` or `/activities/to-me`.
///
/// A post-shaped activity carries the post; the relationship ones carry an actor and
/// sometimes a target, which is either an account or a hashtag.
final class Activity {
  const Activity({
    required this.id,
    required this.kind,
    required this.createdAt,
    required this.unread,
    this.post,
    this.actor,
    this.targetUser,
    this.targetTag,
  });

  /// The opaque `event_key`, which is also what `/read` takes.
  final String id;
  final ActivityKind kind;
  final DateTime createdAt;
  final bool unread;

  final Post? post;
  final UserRef? actor;
  final UserRef? targetUser;
  final String? targetTag;

  Activity read() => Activity(
    id: id,
    kind: kind,
    createdAt: createdAt,
    unread: false,
    post: post,
    actor: actor,
    targetUser: targetUser,
    targetTag: targetTag,
  );

  factory Activity.fromJson(Map<String, dynamic> json) {
    final payload = json['payload'] as Map<String, dynamic>? ?? const {};
    // A post payload is the post itself; anything else is {actor, target?}.
    final isPost = payload.containsKey('body');
    final target = payload['target'] as Map<String, dynamic>?;
    return Activity(
      id: json['id'] as String,
      kind: ActivityKind.fromJson(json['type'] as String?),
      createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
      unread: json['unread'] as bool? ?? false,
      post: isPost ? Post.fromJson(payload) : null,
      actor: switch (payload['actor']) {
        final Map<String, dynamic> actor => UserRef.fromJson(actor),
        _ => null,
      },
      targetUser: target != null && target.containsKey('handle')
          ? UserRef.fromJson(target)
          : null,
      targetTag: target?['tag'] as String?,
    );
  }

  @override
  bool operator ==(Object other) => other is Activity && other.id == id;

  @override
  int get hashCode => id.hashCode;
}

/// One cursor-paginated slice. `nextCursor` is null when the feed is exhausted.
final class Page<T> {
  const Page({required this.items, required this.nextCursor, this.hasUnread = false});

  final List<T> items;
  final String? nextCursor;

  /// Activity feeds only: whether anything unread remains anywhere in the feed, not
  /// just on this page. Cheaper than counting, and it is what drives the tab dot.
  final bool hasUnread;

  bool get hasMore => nextCursor != null;

  static Page<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) decode,
  ) => Page(
    items: [
      for (final item in json['data'] as List) decode(item as Map<String, dynamic>),
    ],
    nextCursor: (json['pagination'] as Map<String, dynamic>?)?['next_cursor'] as String?,
    hasUnread: json['has_unread'] as bool? ?? false,
  );
}

/// The server's `{"error": {"code", "message"}}` envelope, kept structured so the
/// UI can distinguish a 404 from a rate limit without matching on strings.
final class ApiFailure implements Exception {
  const ApiFailure({
    required this.code,
    required this.message,
    required this.status,
    this.retryAfter,
  });

  final String code;
  final String message;
  final int status;

  /// From `Retry-After`.
  final Duration? retryAfter;

  bool get isNotFound => status == 404;
  bool get isRateLimited => status == 429;

  /// The token was rejected. The only reason to sign someone out.
  bool get isUnauthorized => status == 401 || status == 403;

  /// Worth trying again later, unchanged.
  bool get isTransient => status == 429 || status >= 500;

  @override
  String toString() => message;
}

/// A signed-in session. The token is an ordinary textlog session, listed and
/// revocable under account security on the website.
final class Session {
  const Session({required this.token, required this.expiresAt, required this.account});

  final String token;
  final DateTime expiresAt;
  final Account account;

  Session withAccount(Account account) =>
      Session(token: token, expiresAt: expiresAt, account: account);

  factory Session.fromJson(Map<String, dynamic> json) => Session(
    token: json['token'] as String,
    expiresAt: DateTime.parse(json['expires_at'] as String).toLocal(),
    account: Account.fromJson(json['user'] as Map<String, dynamic>),
  );
}

final class Account {
  const Account({required this.handle, required this.bio, required this.canPost});

  final String handle;
  final String bio;

  /// False until the address is verified, which the server requires before posting.
  final bool canPost;

  Account withBio(String bio) => Account(handle: handle, bio: bio, canPost: canPost);

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    handle: (json['handle'] as String).toLowerCase(),
    bio: json['bio'] as String? ?? '',
    canPost: json['can_post'] as bool? ?? false,
  );
}
