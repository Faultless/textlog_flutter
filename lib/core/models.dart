/// Immutable mirrors of the shapes documented at https://textlog.cc/api/openapi.json
library;

final class Author {
  const Author({required this.handle, required this.url});

  final String handle;
  final Uri url;

  factory Author.fromJson(Map<String, dynamic> json) => Author(
    handle: json['handle'] as String,
    url: Uri.parse(json['url'] as String),
  );
}

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
  });

  final int id;
  final String body;
  final DateTime createdAt;
  final int? parentId;
  final int replyCount;
  final List<String> tags;
  final List<String> mentions;
  final Uri url;
  final Author author;

  bool get isReply => parentId != null;

  factory Post.fromJson(Map<String, dynamic> json) => Post(
    id: json['id'] as int,
    body: json['body'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    parentId: json['parent_id'] as int?,
    replyCount: json['reply_count'] as int,
    tags: List<String>.from(json['tags'] as List),
    mentions: List<String>.from(json['mentions'] as List),
    url: Uri.parse(json['url'] as String),
    author: Author.fromJson(json['author'] as Map<String, dynamic>),
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
    required this.followerCount,
    required this.followingCount,
    required this.url,
  });

  final String handle;
  final String bio;
  final DateTime createdAt;
  final int postCount;
  final int followerCount;
  final int followingCount;
  final Uri url;

  factory Profile.fromJson(Map<String, dynamic> json) => Profile(
    handle: json['handle'] as String,
    bio: json['bio'] as String,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    postCount: json['post_count'] as int,
    followerCount: json['follower_count'] as int,
    followingCount: json['following_count'] as int,
    url: Uri.parse(json['url'] as String),
  );
}

/// One cursor-paginated slice. `nextCursor` is null when the feed is exhausted.
final class Page<T> {
  const Page({required this.items, required this.nextCursor});

  final List<T> items;
  final String? nextCursor;

  bool get hasMore => nextCursor != null;

  static Page<T> fromJson<T>(
    Map<String, dynamic> json,
    T Function(Map<String, dynamic>) decode,
  ) => Page(
    items: [
      for (final item in json['data'] as List) decode(item as Map<String, dynamic>),
    ],
    nextCursor: (json['pagination'] as Map<String, dynamic>)['next_cursor'] as String?,
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

  factory Account.fromJson(Map<String, dynamic> json) => Account(
    handle: json['handle'] as String,
    bio: json['bio'] as String? ?? '',
    canPost: json['can_post'] as bool? ?? false,
  );
}
