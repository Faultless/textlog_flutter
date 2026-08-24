/// Deciding what to notify about, as a pure function.
///
/// Everything that could get this wrong lives here rather than in the background
/// isolate: which activities are worth a notification, what each one says, and — most
/// importantly — which ones have already been announced. A background poll runs every
/// fifteen minutes and sees the same activity over and over, so "have I already said
/// this" is the whole problem, and it is one that is much easier to test than to debug
/// on a phone.
library;

import 'models.dart';
import 'polls.dart';
import 'post_context.dart';

/// The kinds of activity worth interrupting somebody for.
///
/// `/activities/to-me` returns exactly replies to you, mentions of you, and follows
/// of you, which is why that is the endpoint the poll reads. These let a reader turn
/// off the ones they do not want.
enum NotifyKind {
  replies('replies', 'when someone replies to you'),
  mentions('mentions', 'when someone mentions your handle'),
  follows('follows', 'when someone follows you');

  const NotifyKind(this.id, this.description);

  final String id;
  final String description;

  static NotifyKind? fromId(String? id) =>
      values.where((kind) => kind.id == id).firstOrNull;
}

/// What the reader has asked to be told about.
final class NotifyPreferences {
  const NotifyPreferences({this.enabled = false, this.kinds = const {}});

  /// Off until somebody turns it on. Nothing polls, nothing is scheduled, and no
  /// permission is asked for.
  final bool enabled;

  final Set<NotifyKind> kinds;

  static const off = NotifyPreferences();

  /// What turning it on gives you before you touch anything else.
  static const defaults = NotifyPreferences(
    enabled: true,
    kinds: {NotifyKind.replies, NotifyKind.mentions, NotifyKind.follows},
  );

  bool wants(NotifyKind kind) => enabled && kinds.contains(kind);

  NotifyPreferences copyWith({bool? enabled, Set<NotifyKind>? kinds}) =>
      NotifyPreferences(enabled: enabled ?? this.enabled, kinds: kinds ?? this.kinds);
}

/// One notification to raise.
final class PendingNotification {
  const PendingNotification({
    required this.activityId,
    required this.kind,
    required this.title,
    required this.body,
    required this.route,
    this.replyToPostId,
  });

  /// The activity's opaque event key, which is also what marks it read.
  final String activityId;

  final NotifyKind kind;

  /// `@alice replied to you`.
  final String title;

  /// The post, or a line describing the follow.
  final String body;

  /// Where tapping it should land.
  final String route;

  /// The post a quick reply would answer. Null for a follow, which has nothing to
  /// reply to — so no reply action is offered on it.
  final int? replyToPostId;

  bool get canReply => replyToPostId != null;

  /// A stable id, so the same activity never appears twice in the shade even if the
  /// watermark is lost and the poll announces it again.
  int get systemId => activityId.hashCode & 0x7fffffff;
}

/// What a poll decided.
final class NotificationPlan {
  const NotificationPlan({required this.notifications, required this.announced});

  final List<PendingNotification> notifications;

  /// Every activity id considered this round, to be remembered so the next poll does
  /// not announce them again.
  final Set<String> announced;

  bool get isEmpty => notifications.isEmpty;
}

/// How many to raise at once. Twenty replies while you were asleep is a summary, not
/// twenty separate interruptions.
const maxNotificationsPerPoll = 5;

/// Work out what to say about a page of activity.
///
/// [alreadyAnnounced] is what previous polls have raised. It is checked *and* extended
/// rather than compared against a high-water mark, because activity ids are opaque
/// strings the server orders by time — there is no "greater than" to compare.
NotificationPlan planNotifications({
  required List<Activity> activities,
  required Set<String> alreadyAnnounced,
  required NotifyPreferences preferences,
  String? viewerHandle,
}) {
  if (!preferences.enabled) {
    return const NotificationPlan(notifications: [], announced: {});
  }

  final notifications = <PendingNotification>[];
  final announced = <String>{};

  for (final activity in activities) {
    // Read on another device, or already announced here.
    if (!activity.unread) continue;
    if (alreadyAnnounced.contains(activity.id)) continue;

    final kind = _kindOf(activity, viewerHandle);
    if (kind == null) continue;

    // Remembered even when the reader does not want this kind, so turning the kind
    // on later does not dredge up a backlog.
    announced.add(activity.id);
    if (!preferences.wants(kind)) continue;
    if (notifications.length >= maxNotificationsPerPoll) continue;

    notifications.add(_describe(activity, kind, viewerHandle));
  }

  return NotificationPlan(notifications: notifications, announced: announced);
}

/// Which of our kinds this activity is, or null if it is not one we notify about.
///
/// A mention wins over a reply: being named is the more specific fact, and it is what
/// the reader turned that switch on for.
NotifyKind? _kindOf(Activity activity, String? viewerHandle) {
  if (activity.kind == ActivityKind.userFollow) return NotifyKind.follows;

  final post = activity.post;
  if (post == null) return null;
  if (viewerHandle != null && post.mentions.contains(viewerHandle)) {
    return NotifyKind.mentions;
  }
  return switch (activity.kind) {
    ActivityKind.reply => NotifyKind.replies,
    ActivityKind.mention => NotifyKind.mentions,
    // `to-me` should not hand us anything else, but a feed that grows a new type
    // must not start notifying about it on its own.
    _ => null,
  };
}

PendingNotification _describe(Activity activity, NotifyKind kind, String? viewerHandle) {
  final post = activity.post;
  if (post == null) {
    final actor = activity.actor?.handle ?? 'someone';
    return PendingNotification(
      activityId: activity.id,
      kind: kind,
      title: '@$actor followed you',
      body: 'Open their profile to follow back.',
      route: '/u/${activity.actor?.handle ?? ''}',
    );
  }

  final relation = postContextOf(post, viewerHandle: viewerHandle);
  return PendingNotification(
    activityId: activity.id,
    kind: kind,
    title: '@${post.author.handle} ${_verb(relation, kind)}',
    // The poll's option lines belong to the poll, not to a notification's preview.
    body: pollDisplayBody(post.body),
    // Straight to the post, not to the feed it came from.
    route: '/post/${post.id}',
    replyToPostId: post.id,
  );
}

/// The same wording the meta line uses, so a notification and the post it opens agree.
String _verb(PostContext relation, NotifyKind kind) {
  if (kind == NotifyKind.mentions) {
    return switch (relation.relation) {
      PostRelation.repliedToYou => 'replied and mentioned you',
      _ => 'mentioned you',
    };
  }
  return switch (relation.relation) {
    PostRelation.repliedToYou => 'replied to you',
    PostRelation.continued => 'continued',
    PostRelation.createdPoll => relation.quiz ? 'created a quiz' : 'created a poll',
    _ => 'replied',
  };
}
