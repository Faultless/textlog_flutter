/// What a post's meta line says about *why* it is in front of you.
///
/// textlog stopped labelling posts with a bare timestamp and started labelling them
/// in words — `@alice replied to @bob:`, `@alice continued:`, `you wrote:`. That
/// reads better and, on a phone, it is the difference between a wall of handles and
/// a conversation you can follow.
///
/// Every input is already on the post: the server inlines the quoted `parent`, so
/// the relation is derivable with no request. Pure, so it is tested against values
/// rather than against a widget tree.
library;

import 'models.dart';
import 'polls.dart';

enum PostRelation {
  /// A top-level post.
  wrote,

  /// A reply to the author's own post.
  continued,

  /// A reply to something of yours.
  repliedToYou,

  /// A reply to somebody else's post, named in [PostContext.target].
  repliedTo,

  /// The body carries a poll.
  createdPoll,

  /// A reply whose parent is gone. The site prints no label at all for this.
  unknown,
}

final class PostContext {
  const PostContext({
    required this.relation,
    required this.mentionedYou,
    this.target,
  });

  final PostRelation relation;

  /// The account replied to, for [PostRelation.repliedTo].
  final Author? target;

  /// The post mentions the signed-in handle, which the site appends to the label.
  final bool mentionedYou;

  /// `wrote`, `replied to`, … — the label as the site words it, without punctuation
  /// and without the trailing `and mentioned you`, which the widget adds so it can
  /// style the two halves differently.
  String? get label => switch (relation) {
    PostRelation.wrote => 'wrote',
    PostRelation.continued => 'continued',
    PostRelation.repliedToYou => 'replied to you',
    PostRelation.repliedTo => 'replied to',
    PostRelation.createdPoll => 'created a poll',
    PostRelation.unknown => null,
  };

  /// Whether anything at all is said. A reply to a deleted post says nothing.
  bool get hasLabel => label != null;
}

/// Work out what to say about [post] to the reader signed in as [viewerHandle].
PostContext postContextOf(Post post, {String? viewerHandle}) {
  final mentionedYou = viewerHandle != null && post.mentions.contains(viewerHandle);

  // A poll is announced as a poll whatever else is true of the post, exactly as the
  // site does — the options are the point, not the reply relation.
  if (parsePoll(post.body) != null) {
    return PostContext(relation: PostRelation.createdPoll, mentionedYou: mentionedYou);
  }
  if (post.parentId == null) {
    return PostContext(relation: PostRelation.wrote, mentionedYou: mentionedYou);
  }

  final parent = post.parent;
  if (parent == null) {
    // The parent was deleted or is otherwise unavailable. Saying "replied to" with
    // nothing after it would be worse than saying nothing.
    return PostContext(relation: PostRelation.unknown, mentionedYou: mentionedYou);
  }
  if (parent.author.handle == post.author.handle) {
    return PostContext(relation: PostRelation.continued, mentionedYou: mentionedYou);
  }
  if (viewerHandle != null && parent.author.handle == viewerHandle) {
    return PostContext(relation: PostRelation.repliedToYou, mentionedYou: mentionedYou);
  }
  return PostContext(
    relation: PostRelation.repliedTo,
    target: parent.author,
    mentionedYou: mentionedYou,
  );
}

/// The label for a quoted parent, where the grandparent is not inlined.
///
/// The server can say `@bob replied to @carol:` inside a quote because it has the
/// whole chain. The API gives a quote no `parent` of its own, so the app can only
/// say that much when the grandparent happens to be in the local cache. [lookUp]
/// gives it that chance without ever costing a request.
PostContext quotedContextOf(
  Post parent, {
  String? viewerHandle,
  Post? Function(int id)? lookUp,
}) {
  if (parent.parentId == null || lookUp == null) {
    return postContextOf(parent, viewerHandle: viewerHandle);
  }
  final grandparent = lookUp(parent.parentId!);
  // Hand the parent its own parent, and the ordinary rules apply.
  return postContextOf(
    grandparent == null ? parent : parent.copyWith(parent: grandparent),
    viewerHandle: viewerHandle,
  );
}
