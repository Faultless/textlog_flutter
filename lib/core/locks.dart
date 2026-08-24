/// Port of the server's lock rule.
///
/// A `#lock` hashtag closes the thread beneath the post that carries it: the server
/// walks the whole ancestor chain and refuses a reply anywhere under it, answering
/// `409 thread_locked`. That refusal is the authority — the app cannot see every
/// ancestor of every post it draws.
///
/// What the app *can* see is enough for the two places a reader meets a lock: the
/// post's own tags, and the parent the API inlines with it. Knowing it early is worth
/// something a 409 cannot buy back — nobody wants to write a reply and be told
/// afterwards that it was never going to be accepted.
library;

import 'models.dart';

/// Does this post carry the lock itself?
bool locksThread(Post post) =>
    post.tags.any((tag) => tag.toLowerCase() == 'lock');

/// Is replying to this post going to be refused, as far as the app can tell?
///
/// [inherited] is for a post drawn inside a thread whose root, or some ancestor
/// further up, already locked it — the tree knows what the post alone does not.
bool threadLocked(Post post, {bool inherited = false}) {
  if (inherited || locksThread(post)) return true;
  final parent = post.parent;
  return parent != null && locksThread(parent);
}
