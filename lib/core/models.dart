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
    this.poll,
    this.linkPreviews = const {},
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

  /// The poll this post carries, from the server rather than parsed out of the body.
  final Poll? poll;

  /// Unfurled cards for the links in the body, keyed by URL.
  final Map<String, LinkPreview> linkPreviews;

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
    poll: switch (json['poll']) {
      final Map<String, dynamic> poll => Poll.fromJson(poll),
      _ => null,
    },
    linkPreviews: {
      for (final entry in (json['link_previews'] as Map<String, dynamic>? ?? const {}).entries)
        entry.key: LinkPreview.fromJson(entry.value as Map<String, dynamic>),
    },
  );

  Post copyWith({String? body, int? replyCount, Post? parent, Poll? poll}) => Post(
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
    poll: poll ?? this.poll,
    linkPreviews: linkPreviews,
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

/// A link's unfurled card, as the server stored it. Keyed by the URL it belongs to.
///
/// The images are textlog's own — it fetches and stores them itself — so showing one
/// costs a request to textlog and reveals nothing to the linked site. That is the
/// whole reason this waited for the API instead of being unfurled client side.
final class LinkPreview {
  const LinkPreview({
    required this.imageUrl,
    this.title,
    this.description,
    this.siteName,
    this.imageWidth,
    this.imageHeight,
    this.mimeType,
  });

  final String imageUrl;
  final String? title;
  final String? description;
  final String? siteName;
  final int? imageWidth;
  final int? imageHeight;

  /// Set for audio and video, which are played rather than shown.
  final String? mimeType;

  bool get isAudio => mimeType?.startsWith('audio/') ?? false;

  /// The card's aspect, for reserving the right space before the image arrives.
  double? get aspect => imageWidth == null || imageHeight == null || imageHeight == 0
      ? null
      : imageWidth! / imageHeight!;

  factory LinkPreview.fromJson(Map<String, dynamic> json) => LinkPreview(
    imageUrl: json['imageUrl'] as String? ?? '',
    title: json['title'] as String?,
    description: json['description'] as String?,
    siteName: json['siteName'] as String?,
    imageWidth: json['imageWidth'] as int?,
    imageHeight: json['imageHeight'] as int?,
    mimeType: json['mimeType'] as String?,
  );
}

final class PollOption {
  const PollOption({
    required this.id,
    required this.label,
    required this.votes,
    required this.selected,
    this.correct,
  });

  final int id;
  final String label;

  /// Null until the result is revealed — the server withholds the tally until the
  /// poll closes or you have voted, so a count cannot influence your choice.
  final int? votes;

  final bool selected;

  /// A quiz only. Null on a poll, and null on a quiz until the reader answers — the
  /// server withholds which one is right for the same reason it withholds the tally.
  final bool? correct;

  factory PollOption.fromJson(Map<String, dynamic> json) => PollOption(
    id: json['id'] as int,
    label: json['label'] as String,
    votes: json['votes'] as int?,
    selected: json['selected'] as bool? ?? false,
    correct: json['correct'] as bool?,
  );
}

/// A poll asks what people think; a quiz has a right answer. Same shape, and the
/// server tells them apart rather than the app guessing from the body.
enum PollKind { poll, quiz }

/// A poll, as the API now returns it.
///
/// The app used to parse this out of the body because it had to. It still parses the
/// body to *strip* the option lines from what it renders, but the options, the tally
/// and whether you voted all come from the server now.
final class Poll {
  const Poll({
    required this.options,
    required this.totalVotes,
    required this.expired,
    required this.expiresAt,
    required this.viewerVoted,
    this.kind = PollKind.poll,
    this.explanation,
  });

  final List<PollOption> options;
  final int? totalVotes;
  final bool expired;

  /// Null on a quiz: a quiz has no deadline, because there is nothing to close —
  /// the answer does not change once enough people have voted.
  final DateTime? expiresAt;
  final bool viewerVoted;
  final PollKind kind;

  /// Why that answer is the right one. A quiz only, and withheld until you answer.
  final String? explanation;

  bool get isQuiz => kind == PollKind.quiz;

  /// The option the author marked right, once the server is willing to say.
  PollOption? get answer {
    for (final option in options) {
      if (option.correct == true) return option;
    }
    return null;
  }

  /// Whether the numbers are showing. The server decides, and it withholds them
  /// until you have had your say.
  bool get revealed => totalVotes != null;

  bool get open => !expired;

  /// Did the reader get it right? Null until they have answered a quiz.
  bool? get gotItRight {
    if (!isQuiz || !viewerVoted) return null;
    for (final option in options) {
      if (option.selected) return option.correct == true;
    }
    return null;
  }

  /// A share of the vote, 0–1, or null while the tally is withheld.
  double? shareOf(PollOption option) {
    final total = totalVotes;
    final votes = option.votes;
    if (total == null || votes == null) return null;
    return total == 0 ? 0 : votes / total;
  }

  factory Poll.fromJson(Map<String, dynamic> json) => Poll(
    options: [
      for (final option in json['options'] as List? ?? const [])
        PollOption.fromJson(option as Map<String, dynamic>),
    ],
    totalVotes: json['total_votes'] as int?,
    expired: json['expired'] as bool? ?? false,
    // Nullable since quizzes landed: they never expire, and reading this as a
    // required string took down every feed page that happened to carry one.
    expiresAt: switch (json['expires_at']) {
      final String at => DateTime.parse(at).toLocal(),
      _ => null,
    },
    viewerVoted: json['viewer_voted'] as bool? ?? false,
    kind: json['kind'] == 'quiz' ? PollKind.quiz : PollKind.poll,
    explanation: json['explanation'] as String?,
  );
}

/// An unpublished post, kept server side so it follows you between devices.
final class Draft {
  const Draft({
    required this.id,
    required this.body,
    required this.parentId,
    required this.createdAt,
    required this.updatedAt,
    this.parent,
  });

  final int id;
  final String body;
  final int? parentId;
  final DateTime createdAt;
  final DateTime updatedAt;

  /// The post this draft is a reply to, inlined.
  final Post? parent;

  bool get isReply => parentId != null;

  factory Draft.fromJson(Map<String, dynamic> json) => Draft(
    id: json['id'] as int,
    body: json['body'] as String? ?? '',
    parentId: json['parent_id'] as int?,
    createdAt: DateTime.parse(json['created_at'] as String).toLocal(),
    updatedAt: DateTime.parse(json['updated_at'] as String).toLocal(),
    parent: switch (json['parent']) {
      final Map<String, dynamic> parent => Post.fromJson(parent),
      _ => null,
    },
  );
}

/// `/explore` — who and what to follow, in one response.
final class Explore {
  const Explore({
    required this.people,
    required this.tags,
    this.peopleCursor,
    this.tagsCursor,
  });

  final List<UserRef> people;
  final List<TagDetails> tags;

  /// Two independent cursors: the two lists page separately.
  final String? peopleCursor;
  final String? tagsCursor;

  factory Explore.fromJson(Map<String, dynamic> json) {
    final data = json['data'] as Map<String, dynamic>? ?? const {};
    final pagination = json['pagination'] as Map<String, dynamic>? ?? const {};
    return Explore(
      people: [
        for (final person in data['people'] as List? ?? const [])
          UserRef.fromJson(person as Map<String, dynamic>),
      ],
      tags: [
        for (final tag in data['tags'] as List? ?? const [])
          TagDetails.fromJson(tag as Map<String, dynamic>),
      ],
      peopleCursor: pagination['people_next_cursor'] as String?,
      tagsCursor: pagination['tags_next_cursor'] as String?,
    );
  }
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

  /// A `#lock` above the post you replied to. The server walks the real ancestor
  /// chain, so this is the authoritative answer where the app could only guess.
  bool get isThreadLocked => code == 'thread_locked';

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
