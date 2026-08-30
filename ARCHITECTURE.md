# Architecture

How this client is put together and why. For what it is and how to run it, see the
[README](README.md); for what is planned, the [roadmap](ROADMAP.md).

## The constraint that used to shape everything

For most of this project textlog's public API was **read-only**: `GET`/`HEAD` only, no
authentication, `CORS: *`. Posting, replying, following and logging in existed solely as
session-cookie HTML form POSTs against unversioned routes, so the app read natively and
handed every write to textlog.cc in a browser tab. The author's position, from
[post 274](https://textlog.cc/post/274):

> if someone wants to implement API authentication and mutation endpoints they are free to try

We did, in [stagas/textlog#3](https://github.com/stagas/textlog/pull/3), and it shipped.
Bearer tokens, `POST`/`PATCH`/`DELETE` on posts, and follow, block and report all live under
`/api/v1/` now, so writing is native.

The API has kept growing since, and the four screens this document used to list as blocked
on the server — the personalised feed, activity, follower lists and a block list — are all
built now. Two of the newer fields changed how the app *fetches* rather than what it shows,
and they are the most consequential things in here: posts inline their quoted `parent`, and
`/posts/{id}/replies` takes a `depth`. See [Quoted parents](#quoted-parents) and
[Nested threads](#nested-threads).

Two things survive from the old shape, and neither is a workaround:

- **Signing up is still a browser tab.** The API refuses to create accounts, deliberately.
  That is where the server puts its abuse controls, and an app that routed around them would
  be the thing everyone was worried about.
- **The layering held.** Adding writes touched `data/api.dart` and added `state/session.dart`.
  Adding four new screens touched `data/api.dart`, added three notifiers under `state/`, and
  changed nothing about how a feed or a thread works.

## Layers

Dependencies point one way only — `ui` → `state` → `data` → `core`.

```
core/    pure Dart. No Flutter, no I/O, no packages.
         models, FeedSource, body tokenizer, block markdown, polls, checklists,
         post context, feed threading, notification planning, the memoised body
         analysis, SSE parser, relative time, the TLD table the autolinker needs.
data/    the only code that talks to the network, plus the OS bridges.
         api.dart, firehose transports, notifications, the background poll, and
         local_store.dart — which owns every SharedPreferences key, because the
         background isolate cannot reach a provider.
state/   Riverpod providers. Thin — they wire data into the widget tree. Session lives here.
ui/      widgets. Pure functions of state.
```

`core/` has no Flutter import, so every rule that decides what the user sees — how a body
is tokenized, what `3mo` means, which URL a feed maps to — is testable without a widget
tree or a server. That is most of `test/core_test.dart`, and it runs in milliseconds.

## The keystone: `FeedSource`

Every scrollable list of posts in the app is one of these:

```dart
sealed class FeedSource {}
  LatestFeed()                    -> feeds/latest
  HotFeed()                       -> feeds/hot
  NotesFeed(handle)               -> users/{handle}/notes
  UserRepliesFeed(handle)         -> users/{handle}/replies
  TagFeed(tag)                    -> tags/{tag}/posts
  RepliesFeed(postId, depth: n)   -> posts/{id}/replies?depth=n
  SearchFeed(query)               -> search?q=…
```

The server returns the same envelope for all of them, so one notifier
(`state/feed.dart`) and one widget (`ui/widgets/feed_view.dart`) serve every feed —
pagination, pull-to-refresh, empty states and error recovery included.

**To add another:** add the class, add its case to `pathOf` and, if it needs query
parameters of its own, to `queryOf`. Done. The exhaustive `switch` in both means the
compiler tells you if you forget. No new notifier, no new list widget, no new error
handling.

`FeedSource` implements `==`/`hashCode` because it is a Riverpod family key — two
`TagFeed('dart')` values must resolve to the same cached provider, and `RepliesFeed(1)`
and `RepliesFeed(1, depth: 5)` must not.

The activity feeds and the relationship lists are *not* `FeedSource`, because they return
different shapes: `state/activity.dart` handles `{data, has_unread, pagination}` and
`state/people.dart` handles lists of `{handle, url}`. Forcing them through one abstraction
would have meant a `Page<dynamic>` and casts at every use.

## Conventions

**Immutable data.** Every model is `final class` with `final` fields. `FeedState` changes
via `copyWith`. Nothing mutates in place.

**Effects at one edge.** `TextlogApi` is the only class that performs I/O. It takes an
injected `http.Client`, so overriding `httpClientProvider` runs the entire app against a
fake server — that is how `test/feed_test.dart` tests pagination with no network.

**Errors are values where it matters.** The API throws a typed `ApiFailure` carrying the
server's `{code, message}`; Riverpod's `AsyncValue` catches it at the provider boundary.
We deliberately do *not* add a `Result<T>` on top — `AsyncValue<Result<T>>` would mean
unwrapping twice for no gain. The one place an error genuinely is a value is
`FeedState.loadMoreError`, because a failed *next* page must not discard the pages already
on screen.

**Exhaustive switches over sealed types** for `FeedSource`, `BodyToken` and `AsyncValue`.
Adding a case becomes a compile error at every site that must handle it.

**No comments that restate the code.** Comments here explain *why* — a workaround, a
constraint, a decision that looks arbitrary until you know the reason.

## Visual identity and themes

Colours in `ui/theme.dart` are textlog's CSS custom properties copied verbatim and kept
under their original names (`--soft` → `Palette.soft`), so a change on the site is a
one-line diff here. Same for the `--space-*` scale and `--gutter`'s `clamp(18px, 3vw, 28px)`.

`Palette` is a `ThemeExtension`, which is why every widget can say `context.palette` without
anyone threading it down. There are four — `light` and `dark` are the site's own, `sepia`
and `dracula` are ours — plus an accent the reader picks. Accents are a curated list rather
than a colour picker: each has a variant tuned for light and for dark backgrounds, so no
choice can produce unreadable links. `withAccent` derives the hover shade by shifting
lightness, darker on light backgrounds and lighter on dark ones, as the site does.

`system` hands the light/dark decision to Flutter so it tracks the device live; a fixed
choice pins both theme slots to the same palette so it cannot.

Two details that carry most of the look: everything is monospace, and links are
accent-coloured with an underline in a *quieter* colour (`linkBorder`) — that is what
stops a dense feed reading as a wall of green.

The body tokenizer in `core/body_tokens.dart` is a direct port of the server's `linkify`
(`src/utils.ts`), including the rule that trailing sentence punctuation stays outside a
URL. Bodies render identically to the website.

## Bodies

`core/body_tokens.dart` is a port of the server's `linkTokens` / `linkify`, and
`core/content.dart` a port of its `content.ts`. Between them they decide what a body *is*:
which hashtags count (unicode, capped at five, ignoring anything inside code or a URL),
whether it is ASCII art, and where a spoiler splits it.

The split that matters is **what is always rendered versus what is opt-in**:

- **Always**, because textlog.cc renders it, and leaving it out would show the reader
  something the author did not write: inline `` `code` ``, ``` fences, `$x$` and `$$x$$`
  LaTeX, `[label](url)`, `*bold*`, `_underline_`, `/italics/`, `~strikethrough~` (one
  tilde, not just two), `|redacted|`, bare and schemeless URLs, mentions, hashtags,
  spoilers, `>` quoted lines, polls and quizzes.
- **Behind the `markdown` setting**, because the site keeps a post body flat: headings,
  ordered and unordered lists, task lists, tables and rules.

The emphasis markers are worth stating plainly, because three of them read as something
else in every other dialect: `*x*` is **bold**, `_x_` is <u>underline</u>, and italics is
`/x/`. Guessing from Markdown habit shows the reader emphasis the author did not write.
`|x|` is a bar you press to reveal — ink on ink rather than a gap, so revealing it does
not reflow the paragraph.

**Quoting is not part of the setting**, though a blockquote sounds like markdown. The
site quotes a `>` line unconditionally, so the app does too — grouping consecutive lines
into one quote, recursing so `> > x` nests, and leaving fenced code alone, which is what
keeps the `> Correct answer` in a *quiz syntax example* literal. It also leaves ASCII art
alone: a drawing's first column is often `>`, and quoting it would take the drawing
apart.

LaTeX renders through `flutter_math_fork` — TeX to Flutter widgets, no webview, works on
web. An expression it cannot parse falls back to the source in a code run, which is what the
site does when MathJax refuses it.

Ordering inside the tokenizer is load-bearing and mirrors the server's own precedence: a
fence beats inline code beats maths beats a markdown link beats strikethrough beats a URL
beats a reference. Markdown links are pulled out before bare URLs or the label would be
lost; maths is scanned outside code spans or `` `$x$` `` would render as maths. A test
asserts that turning the setting on never changes what gets linked.

Polls live in the body — a line ending `#poll`, then the options — so `core/polls.dart`
parses them and `pollDisplayBody` strips the option lines before rendering. Without that
the options render as ordinary text.

## What a post's meta line says

`core/post_context.dart` decides whether a post `wrote`, `continued`, `replied to you`,
`replied to @someone` or `created a poll`, and whether to append `and mentioned you`. All of
it is derivable from what the post already carries — the inlined parent and the `mentions`
array — so the words cost nothing.

A quoted parent is the one case with less to go on: the API gives a quote no parent of its
own, so the grandparent's handle is unknown. `quotedContextOf` takes a lookup and consults
the local post cache, which very often has it because the grandparent was just on screen.
When it does not, the quote says less rather than costing a request.

## Live tab

`/api/v1/firehose` is an SSE stream of every new post. `package:http` buffers whole
responses in the browser, so the transport is conditionally imported — a streamed request
on mobile, native `EventSource` on web — while the parser (`core/sse.dart`) is shared and
pure. The server allows three streams per IP.

### The stream does not stay up, and cannot be made to

An idle firehose connection dies after about twelve seconds. The server does send a
keep-alive, but on a fifteen-second timer, so it never fires in time — whatever sits in
front of the app (it answers `via: 1.1 Caddy`) drops the connection first. Measured with
curl, over both HTTP/1.1 and HTTP/2, it was twelve seconds every time. While posts are
actually flowing the bytes keep it open, so this bites hardest exactly when the community
is quiet.

Nothing in the client can fix that; it is a server-side timer. The upstream fix is a
heartbeat shorter than the proxy's idle timeout. So the client is built to expect the
churn instead:

**Reconnect fast, don't back off.** An earlier version treated a twelve-second session as
unhealthy and doubled its retry delay out to thirty seconds, which missed far more than it
caught. A close after a successful connection is now normal — retry in a second. Exponential
backoff is reserved for real failures: refused, rate limited, offline.

Feed reads carry the session token now. Not for the unread state alone: an anonymous
read applies no viewer, so the accounts and hashtags the reader had *blocked* came
back in their own feeds. It also counts against the higher authenticated limit.

The read limit is counted per *account* now, not per IP, and is 600 a minute signed in
against 120 anonymous. Nothing in the app encodes those numbers — it reacts to a 429 and
its `Retry-After` — but it is why a signed-in reader can page a long thread without ever
meeting the gate, and why the live test suite is much less likely to trip over itself.

**Reconcile, because the gap loses posts.** The server does not honour `Last-Event-ID`; a
new connection simply subscribes to future posts, so anything published while it was down
is gone as far as the stream is concerned. On every connect the live feed fetches
`/feeds/latest` and merges what it missed, deduplicated by id.

The mark it compares against is fixed at the moment the tab opened, **not** the newest post
seen. That distinction is load-bearing: a moving mark loses posts, because a live post
arriving before reconciliation finishes pushes the mark past older posts still missing from
the gap, and they never arrive. There is a test for exactly that.

## Routing

Routes mirror the website — `/for-you`, `/to-me`, `/hot`, `/latest`, `/live`, `/search`,
`/post/:id`, `/u/:handle?tab=…`, `/tag/:tag` — so on web every screen has a shareable URL
and "open on textlog.cc" is a straight passthrough. `/live` is the one path the site does
not have.

`/` redirects rather than rendering: the site sends an anonymous reader to `hot` and a
signed-in one to their own feed, so the router is built from a `Ref` and reads the session
to answer it.

Deep links need a server rewrite, which GitHub Pages does not do — the deploy workflow
copies `index.html` to `404.html`, and that is what makes a cold load of `/post/328` work.

Two web-only settings in `main.dart` earn their keep. `usePathUrlStrategy()` — without it
web URLs are hash-based and `/tag/open_source` never reaches the router.
`GoRouter.optionURLReflectsImperativeAPIs` — without it `push` keeps the back stack but
leaves the address bar showing the page you just left.

`SemanticsBinding.instance.ensureSemantics()` publishes the semantics tree on web. Flutter
paints into a canvas, so without it the page is opaque to screen readers and to browser
automation alike.

## Where a tap goes

Two rules, both learned from the same report: a checklist item that could not be ticked
because the card underneath it kept opening the post.

**The innermost thing with an action wins.** That is already how Flutter resolves a gesture
arena, so a link span or a checkbox inside a tappable card needs nothing special — *as long
as it has an action*. The trap is `onTap: null`: no recognizer is created, the tap falls
through to the card, and a control that looks pressable does something unrelated. So a
checkbox and a poll option pass `onTap ?? () {}` and absorb their own tap even when they
cannot act on it, while `Semantics(button:)` still reports the truth to a screen reader.

**Nothing navigates to the page it is already on.** A post is reachable from its card, its
timestamp, a quoted parent and the `top` link, and on the page that post is *about* every
one of them used to push the route already showing — stacking a second copy, then a third.
`openPost` in `ui/router.dart` compares against `GoRouterState.of(context)` and returns
instead, so the guard cannot be forgotten by the next thing that navigates to a post. The
subject card goes further and takes no `onTap` at all, so it does not offer a press that
would do nothing.

`openLink` sits next to it for links out of a body or a preview card. `core/app_links.dart`
maps a URL to a route, purely: same host as `linkOrigin`, a path it recognises, and back
comes `/post/2201` or `/u/stagas` to push. Anything else — another site, a lookalike host
like `textlog.cc.example`, `/account/...` which has no screen here, a `javascript:` URI —
returns null and goes to the browser. Keeping it pure is what makes the browser cases
cheap to test, and they are the ones worth testing.

## Locked threads, and why the app guesses

A `#lock` closes the thread beneath the post carrying it. The server walks the real
ancestor chain and answers `409 thread_locked` to any reply under it, so that refusal is
the authority — `core/locks.dart` cannot be, because the API does not put `thread_locked`
on the post shape and the app cannot see every ancestor of every post it draws.

So it guesses, deliberately, from the two things it *can* see: the post's own tags, and
the parent the API inlines with it. A thread page seeds the flag from its subject and
`ReplyBranch` carries it down, because a reply cannot see past its own parent — including
through `FlatReplies`, where a post no longer sits under the ancestor that closed it and
so cannot work it out from its position at all. Guessing early buys something the 409
cannot give back: nobody wants to write a reply and be told afterwards that it was never
going to be accepted.

## Opening the app

A cold start used to show a signed-out app that changed its mind: `sign in` in the
header, no account tabs, an empty feed with a spinner — and then, once a local read
and a network round trip had finished, the whole thing rearranged itself. Two
separate causes, and both are worth stating because both are easy to reintroduce.

**An `AsyncNotifier`'s first state is `loading`, even when its `build` awaits
nothing.** So `ref.watch(sessionProvider).valueOrNull` is null on the first frame no
matter how fast the session resolves, and every widget asking "am I signed in"
answered no. `LocalStore.prime()` now opens storage once before `runApp`, and
`viewerProvider` returns the stored session while the real one is still coming.
**The UI reads `viewerProvider`**; `sessionProvider` is for the token and the actions
on its notifier. The confirmation runs behind the reader: it fills in the rest of the
account, and only a *rejected* token clears the session — being offline is not
evidence that anyone signed out.

**And there were no posts to show.** The caches were all in memory, so every launch
started from nothing. `data/feed_store.dart` keeps the last page of `hot` and
`latest` on disk — the server's own JSON, parsed back through the same
`Page.fromJson` the network path uses, so there is no second serialiser to drift and
a stored feed either decodes exactly or is discarded. It goes up immediately and the
network replaces it in place.

Three things about that are load-bearing:

- **In place, not by invalidating.** `refresh()` invalidates, which builds a new
  notifier, which reads the same stored page and revalidates again — forever. The
  revalidation writes `state` directly.
- **Offered once per session.** A stored page is for a cold start. Every later build —
  a pull to refresh, the invalidation after posting — must reach the server, or the
  reader would be shown the page from before their own write.
- **Keyed by who read it.** A signed-in read applies that reader's blocks and carries
  their unread state, so the key carries their handle. One shared key would show a
  stored timeline to whoever opened the app next.

Two days is the shelf life. Posts carry a relative timestamp, and `3h` on a week-old
post is a lie that the refresh would only correct afterwards.

## Reading preferences

The site has one appearance panel; a phone needs a few more decisions, because the
page is smaller and because what one reader wants out of the way is what another
reads for. All of them persist, all default to how the app shipped, and none of them
change what the server sends.

- **Timestamps and reply counts** can each be turned off. The stamp doubles as the
  link into a post, so losing it costs something — the card still opens the post, and
  with both off `PostMeta` draws nothing rather than an empty tap target.
- **Follow notices** filters follows and tag-follows out of `for you`. Done in the
  app because the server offers no such parameter, which has a consequence worth
  knowing: the unread count it reports can exceed what is on screen, and a hidden row
  is never marked read on the reader's behalf.
- **Tabs** can be reordered and hidden. `core/tab_prefs.dart` is the rule, and every
  interesting case in it is a disagreement between a stored preference and the tabs a
  build actually offers: a tab added by a later version is **appended** rather than
  dropped, one that no longer exists is dropped, and hiding everything still leaves
  one standing — a tab row with nothing in it is an app with no way back to the
  setting that broke it. A hidden tab still renders when reached by its own URL;
  hiding is about the row, not about walling off a link someone sent you.
- **Swipe to reply** drags a post leftwards. Leftwards deliberately: a rightward drag
  from the edge is the system back gesture on both platforms, and competing with that
  would break something people rely on to win something they do not yet know exists.
  The inner horizontal scroll of a wide code block still wins its own gesture, being
  deeper in the hit test — there is a test for that, because the alternative is a post
  whose code cannot be read.

## What a retry has to look like

Riverpod keeps the previous error while a provider rebuilds — `AsyncLoading`
`copyWithPrevious` an `AsyncError` is still an `AsyncError`, with `isLoading` set. So the
error branch of every screen rendered again during a retry: same message, same button, no
spinner. Tapping retry was indistinguishable from tapping nothing, twice over on a network
that failed again, and people pulled down to refresh instead — which worked, because a
`RefreshIndicator` has a spinner of its own.

`StatusMessage` is stateful for that one reason. It awaits the callback, says `retrying…`
while it waits, and stops accepting taps until it returns. Which means **`onRetry` has to
return a future that completes when the refetch does** — `notifier.refresh()`, or
`ref.refresh(provider.future)`. A bare `ref.invalidate` returns before there is anything to
wait for, so the label would flash for one frame and the screen would go back to looking
inert. Every call site was changed to the future form for that reason.

The button keeps its place while it waits rather than being replaced by a spinner: moving
the thing you just pressed out from under your finger is its own small insult.

## Writes

`ui/widgets/compose_sheet.dart` is one form for posting, replying and editing, because on
textlog those are the same 500 characters and the same button. `ui/widgets/post_actions.dart`
returns the row of actions as loose widgets rather than a widget of its own, so they sit on
the same line as the handle and the time the way `.posttop` does on the site.

**After a write lands, nothing refetches if it does not have to.** An edit comes back fully
formed, so it is written straight into the post cache, into every cached reply list holding
it, and into any live feed showing it. A delete removes it from the same three places. Only
a reply invalidates, because a new post has an id and a timestamp that only the server knows.
Deleting the post a screen is *about* navigates to its parent; deleting from a feed or a
profile leaves you where you were, with the post simply gone.

**Signed out, the old path is still there.** `openReply` and friends
(`ui/screens/web_action.dart`) open textlog.cc in the *system browser's* tab, which is also
what makes the app usable against a server without the write endpoints. A browser tab, not a
WebView: an embedded WebView keeps a private cookie jar, so a magic link opened in the
device's default browser would sign you into a session the app could never see. The first cut
used `webview_flutter` and had exactly that bug. The fix removed a dependency.

Android 11+ hides other installed apps unless they are declared, so
`android/app/src/main/AndroidManifest.xml` carries a `<queries>` entry for `https` VIEW
intents. Without it `url_launcher` cannot resolve a browser and the fallback silently does
nothing.

## Accounts

`state/session.dart` holds a bearer token and the account it belongs to, in
`shared_preferences`. On launch it validates the token against `GET /api/v1/me`: an
`ApiFailure` means the session is gone and it clears, while any other error means the phone
is offline and it trusts what it stored rather than signing a reader out over bad reception.

The token is an ordinary textlog session. It appears under account security on the website
alongside browser sessions and can be revoked there, which is the property that makes it
reasonable for an app to hold one at all.

Signing in is two steps: an email address, then the six-digit code the server mails back.
The app never handles the magic link itself. That was a deliberate call, made back when it
looked like a shortcut: `/enter/magic` deletes the token in the same transaction that creates
the session, and `issueMagicLink` invalidates any earlier link for the same address, so one
link yields exactly one session. An app that claimed it would leave your browser logged out.
The code is a second door to the same flow, added in the same PR as the write endpoints.

If the server has no write endpoints, signing in returns a 404 and the sign-in screen offers
to remember your handle instead (`state/identity.dart`). That is identity rather than
authentication, it gates nothing, and `/api/v1/users/{handle}` is public. A storage failure
is treated as "we don't know who you are" rather than an error state, because blocking a
reader behind a preferences read would be absurd.

## Caching

`cacheFor` in `state/cache.dart` keeps an autoDispose provider alive for five minutes after
its last listener goes, instead of dropping it the moment you navigate away. Without it,
tapping into a thread and pressing back refetches the feed and throws you to the top, which
is the single thing that makes a Flutter app feel like a website.

`PostCache` holds posts already seen in any feed. Tapping a post is the most common
navigation in the app, and its target is nearly always something that was just on screen, so
that transition costs no request at all. Bounded to 500 entries, oldest evicted first.

The cache has one sharp edge worth knowing: `postProvider` serves from it, so invalidation
alone would hand back the same copy. Everything that changes a post calls `forget(id)` or
`replace(post)` *before* invalidating, or refreshing after a write would be a no-op. There is
a test for exactly that.

## Nested threads

`/posts/{id}/replies` takes a `depth` of 1 to 20 and returns the **whole subtree, flat** —
every reply carrying its own `depth` and `parent_id`. So a thread is one request, and
`state/thread.dart` groups the response by parent and hands it to the pure assembler in
`core/reply_tree.dart`.

It did not used to be. The endpoint returned direct children only, so a nested thread cost a
request per branching node: `maxThreadRequests` was 8, the walk was breadth-first and
concurrent, and a wide thread still ran out of budget. All of that machinery is gone.

What remains is the part that was always the good idea: **`reply_count` is the change
signal.** Every post says how many replies it has, so a node whose children the response
could not reach — because it sat past `maxThreadDepth`, or because the 100-post page cut it
off — shows `+ N more replies` rather than a silently short branch. Tapping it is one more
request for that subtree.

Two subtleties in the grouping, both covered by tests:

- The server returns the **newest** N of the subtree. A newest-N slice can contain a reply
  whose parent was cut off, and such an orphan cannot be placed anywhere sensible — so it is
  dropped and its ancestor advertises the gap instead.
- Replies come back newest-first; a thread reads oldest-first. Sorting by id ascending also
  guarantees a parent is seen before its children, which is what makes the single grouping
  pass work.

### `reply_count` is a whole descendant count

Not a direct-child count. Three separate bugs came from treating it as one, and all
three showed up as "the +N more link does nothing":

- **The count itself.** `unloaded` was `reply_count` minus the number of *direct*
  children drawn, so a node whose whole visible branch was already on screen still
  advertised replies. It is now `reply_count` minus everything rendered beneath the
  node — like against like.
- **What the link did.** It offered to load in place regardless of whether that could
  put anything on screen. Past the nesting cap there is nowhere to draw a reply, so the
  tap spent a request and left the tree exactly as it was. A node now carries
  `expandable`, true only when fetching would actually add children *here*; everything
  else opens the post, which is where those replies can be seen.
- **Cache invalidation.** `noticeCounts` compared the incoming `reply_count` against
  the number of children held, so nearly every node with a grandchild looked stale and
  had its replies thrown away on every feed fetch. It now compares against the count
  observed when those replies were cached, and says nothing when it never saw one.

Because ids only ever increase, a post that made it into a page brings all its
descendants with it — a page can never separate a node from its own children. So
in-place expansion exists for one case only: a branch whose cached replies were dropped
because the server reported a different count.

### A page whose newest replies are all deep

`/replies` returns the **newest** hundred of a subtree, which is not the top hundred. A
busy branch deep in a thread can fill the page and leave its own ancestors off it, and
those posts cannot be placed by `parent_id` alone. Dropping them meant a thread with a
hundred and twenty replies rendered as empty.

Two passes fix it. The first places what it can; the second rebuilds one missing level
from the `parent` the server inlines on every post — free, no request. When more than one
level is missing, and only then, one request for the root's direct children guarantees
the thread is never blank when it has replies.

### Not refetching what we already have

`RepliesCache` holds two things: the direct children of each parent, and a mark recording
that a *subtree* rooted at some id was fetched to some depth. The children are what the tree
is assembled from; the mark is what stops reopening a thread paying for it again.

The depth is recorded per node, not just per request: a node three levels into a five-level
fetch has two levels below it, so it is marked as covered to depth two. Without that,
opening that node's own page would reuse the cache and show a shallower tree than a fresh
request would.

Invalidation is deliberately asymmetric. `forget(id)` drops that parent's children *and* the
subtree mark rooted there, but leaves marks rooted **above** it alone — assembling from one
of those will find no entry for the forgotten parent and advertise its replies as unloaded,
which is the honest answer and costs one tap rather than refetching a whole thread. A
`reply_count` that disagrees with what we hold goes through the same path.

## Feed threads

A feed that returns twenty replies to one conversation used to render twenty posts, each
quoting the same parent underneath it. `core/feed_tree.dart` joins any reply whose parent
is *also on the page* under that parent instead — the change the site made for the same
reason, and worth more on a phone, where the duplication cost the most scrolling. On a
live page of twenty, six posts nest and six duplicated quotes disappear.

It needs nothing the feed does not already carry: `parent_id` for the join, and the
inlined `parent` for the case where the parent is not on the page.

Two things it must never do, both tested:

- **Lose a post.** A chain deeper than the nesting cap does not get truncated; the chain
  restarts as a new block each time it would nest too far.
- **Swallow a page.** Ids only ever go up, so a cycle cannot happen — but if one did, a
  grouper that found no roots would render nothing at all. Anything whose parent has not
  been assigned yet becomes a root.

## Quoted parents

A reply renders the post it answers in a tinted box beneath it, as the site does. **The
server inlines it**: every post-bearing response carries its `parent`, so a feed of fifty
replies costs one request where it used to cost fifty-one.

`PostCache.remember` writes inlined parents in as well, which is what makes tapping a quote
free. It merges rather than overwrites: a quoted copy carries no parent of its own, so
taking it wholesale over a fuller copy would lose a grandparent we already knew.

A `parent_id` with no `parent` means the parent is gone. The site prints `(deleted post)`
and links to it; so does this.

## Known gaps

- **Images in a post body.** The server degrades these to a link; the app does the same.
- **A truncated following list.** `Relationships` walks at most five pages, and an account
  missing from a truncated list is reported as *unknown* rather than absent — so a follow
  button says `follow` without the arrow instead of claiming you do not follow someone you
  do. Acting on an account settles it either way.
- **A thread wider or deeper than one page.** 100 posts at depth 5 covers virtually
  everything; past that, branches advertise what is missing.
- **A pinned post is drawn separately, not sorted.** The API returns `pinned_note` and
  `pinned_reply` on the profile rather than sorting them to the top of the list the way
  the website does — `profile_pinned` is on the website's own post shape, not the API's.
  So the app draws the pinned post above the list under a `pinned` label and leaves it
  out of the list, which says the same thing without pretending to an ordering the
  server did not give.
- **Moderation.** The server classifies posts and the website has a consent screen for
  showing what it flagged. `moderation_category` and `moderation_score` are on the
  website's own post shape, not the API's, so the app cannot see the flag to act on it.
- **A direct reply count.** `direct_reply_count` landed upstream — the number a reader
  would actually count — but on the website's shape only. The app still works from
  `reply_count`, which is the whole descendant count, and subtracts what it has
  rendered to decide what is missing.

## Polls, checklists and link previews

All three used to be impossible and are not any more, and each landed differently.

**Polls** are on the post shape now, so the app stopped parsing them out of the body —
except for one thing: the option lines are still *part* of the body, so they have to be
stripped from what renders above the poll. The tally is withheld by the server until the
poll closes or you have voted, which is why `votes` is nullable rather than zero, and why
that is a state the UI has to draw rather than an error.

**Quizzes** are polls with a right answer: `#quiz` instead of `#poll`, the answer marked
`>`, and an optional explanation after a blank line. Three things follow from the server's
shape, and each of them is a UI state:

- `expires_at` is **null**, because a quiz has no deadline — there is no tally to settle.
  Reading it as a required string is what took down every feed page carrying a quiz, and
  the nullability is now the thing a test pins.
- `correct` and `explanation` are withheld exactly as `votes` is, so a quiz reads like a
  poll until you commit to an answer. The optimistic copy written on tap deliberately
  does *not* fill them in — guessing would give the answer away a round trip early.
- The verdict is a tick or a cross as well as a colour. Green-versus-red says nothing to
  a reader who cannot tell those two apart.

**Checklists** are the opposite: entirely in the body, with no endpoint. Ticking one
rewrites the body and saves it as an edit, so only the author can tick their own list.
That is the site's rule and a consequence of the design, not a gap in the client.

**Link previews** are on the post shape too, and the images are textlog's own — it fetches
and stores them itself, so showing one reveals nothing to the linked site. That is exactly
why this waited: unfurling client side would have meant a request per link to a third
party and every reader's address handed to every site anyone linked.

Two things about drawing them, both found on a device:

- **A thumbnail, not a hero.** One preview on textlog is 1191×1684; at its own aspect that
  is 475px of a phone screen, burying the post that linked it. A fixed square crop beside
  the text is predictable whatever the source shape, and a preview with no image is a
  compact line rather than a card with a hole in it.
- **Never ask for the whole of an unbounded axis.** `CrossAxisAlignment.stretch` and
  `width: double.infinity` both resolve against the incoming maximum extent, which inside a
  scrollable is infinite — so they throw during layout and take the whole page down, post
  and replies and all. It cost a blank thread twice: once here, and once in a code block
  filling its own sideways viewport. Where a child really should span the column, measure it
  with a `LayoutBuilder` *outside* the scroll view and set a `minWidth`; that grows a narrow
  child without capping a wide one.
- **No images on the web build.** textlog serves preview images from a host that sends no
  `Access-Control-Allow-Origin` at all, and Flutter's canvas renderer fetches images with
  XHR. Rendering an `<img>` element instead escapes Flutter's layout and fills the screen,
  which is worse than not having the picture — so web gets the compact form.

## Code that ran, and places

Two more things that live on the post shape rather than in the body, and both are the
same argument: the server did the work, so the app does not.

**`execution_output`** is what the code fence under a `#exec` line printed when the
server ran it — once, when the post was written. Nothing executes on the phone and
every reader sees the same characters. How much of it is shown is the client's job,
and `core/execution.dart` is the site's rule ported rather than invented: ten lines
with the last one kept, two hundred characters a line, and the sandbox's own kill
message dropped. An empty string is a program that printed nothing, which is not the
same as no output, and draws no box.

**`location`** is a `#map` post's place, geocoded by the server, with a map tile the
server rendered and stored. So the card is a picture from textlog and a link to
whichever maps site it picked — the app geocodes nothing and the reader's own location
is never involved. It is drawn as a link preview card, because that is exactly what
the server sends.

**Coloured code fences** are the one thing here the server cannot hand over: it
highlights `js` and `python` with highlight.js and sends HTML to a browser, while the
API sends the body as it was written. `core/highlight.dart` is a hundred-line scanner
over comments, strings, numbers and keywords in the same four colours the site's
stylesheet gives those classes. Deliberately not a parser: it cannot fail on code it
does not understand, and the worst it does is leave a run plain. Every other language
comes back as one run, so a fence in anything else costs nothing.

## Bookmarks

`POST`/`DELETE /posts/{id}/bookmark` and `GET /bookmarks`, which is a page of posts
like any other feed — so it is a `FeedSource` and the pagination, errors and rendering
came along unchanged.

The one wrinkle is that a post does not say whether it is bookmarked: there is no such
field on the post shape, and the only posts whose state is known are the ones in
`/bookmarks` and the ones bookmarked here since launch. `state/bookmarks.dart` is
therefore a `Map<int, bool>` where **absent means unknown**, not "no". The menu offers
`bookmark` when it does not know, which is safe because both routes are idempotent —
and the bookmarks screen tells the map what it loaded, so the menu on those posts can
offer to remove instead.

## The site's names

The site renamed three feeds — `to me` is `@`, `for you` is `my feed`, `latest` is
`all` — and the app follows it in the two places a person can see: the tab labels and
their order. The enum names, the app's own routes and the ids in anyone's stored tab
arrangement deliberately did not change, because those are not words anybody reads and
changing them would silently reset a setting.

The API paths did not change either. `/feeds/latest` and `/activities/for-you` are
documented as backward-compatible aliases of the new spellings, which means the old
names work against every server the app might meet and the new ones only work against
a new one. `core/app_links.dart` knows both spellings, so a link written a year ago
still opens in the app rather than bouncing to a browser.

## Voice clips

A Vocaroo link plays where it was linked, streamed from textlog's own
`/media/vocaroo/{id}` — a plain ranged mp3. Going through the proxy is the point:
listening tells Vocaroo nothing, which is the same reason link previews are fetched
server side.

Three things are load-bearing:

- **Two URLs, and they are not interchangeable.** The link identifies the clip among
  others on the page; the proxy is where the bytes are. Handing the link to the player
  asks it to decode Vocaroo's *web page*, and the failure surfaces as
  `UnrecognizedInputFormatException` — which reads as an unplayable clip rather than
  the mix-up it is. A test pins the two apart at the boundary where they meet.
- **One player for the app**, in `state/audio.dart`, with `playingClipProvider` naming
  the clip that owns it. Two clips playing over each other is never wanted, and a
  player per card would hold a decoder open for every card that scrolled past.
- **Created only on first press.** The card watches which clip is playing, not the
  player, so a feed full of clips costs nothing until one is pressed — and a widget
  test can render one with no platform channel at all.

Vocaroo sends no preview metadata, so there is no card to attach this to: the
preview is synthesised from the body's own links, and only when the server sent no
real preview to show first.

## Parsing a body once

Rendering a body asks a lot of questions about it — poll, checklist, spoiler, ASCII art,
links, mentions, blocks — and each is a pass over the string. `build` runs on every frame
a tile is scrolled through, and that measured at around 300µs per body per build on a
desktop. On a debug build on a mid-range phone it was enough to hang the app outright.

A body is an immutable string, so `core/body_analysis.dart` works all of it out once and
keeps the answer in a bounded, insertion-ordered map. A rebuild is a lookup. The test
asserts the cached answer is *identical*, not merely equal, and that it agrees with parsing
by hand — a cache that changes the answer is worse than no cache.

## When something counts as read

An activity used to become read only if you tapped it, which meant scrolling through
everything addressed to you left every dot in place — and the only way to clear them
was "mark all as read", a chore the reader had already done by reading. Scrolling
marks things read now, and getting that to feel right took three separate rules.

**A slice showing is enough.** The first version required a row to be *fully* inside
the viewport, and that was wrong in both directions: the post filling the screen is
never fully inside it, the post you have obviously started at the bottom edge is not
either, and a post taller than the viewport could never be marked at all. So a row
counts once `seenSlice` pixels of it are showing — or, for a row shorter than that,
once all of it is. The only thing the bar excludes is the hairline of the next post,
which is always poking in at the edge and is the thing you are scrolling *towards*.
`core/seen.dart` is that rule and nothing else, so it can be argued with in a test
rather than on a device; the widget only measures and reports rectangles.

**Every scroll notification, not only the end of one.** A post is read when it comes
into view, not when the thumb finally lets go. Measuring a dozen render boxes per
frame is nothing; it is the *requests* that would be absurd, so `state/read_queue.dart`
holds the ids for a moment and sends them together — a fling through forty posts is
one request. The queue also flushes when the notifier is disposed, because the last
few posts of a session are exactly the ones whose rails would otherwise be back next
launch. Ids already sent are remembered, since the notifier is optimistic and a row
stops being unread locally before the request lands.

**A block, not a row.** A feed page joins replies to parents that are on it, so one
block on screen can hold several unread posts while only its top is measured. Passing
the block passes all of them — `unreadIn` in `core/unread.dart` — and without that a
feed that had visibly been read could never empty, because the replies inside it were
never named to the server.

A sweep also runs after any build that has data: at open there has been no scroll to
notice, and the first screenful would otherwise be the one part that never marks
itself.

## The catch-up set

Marking by reading only works if the unread pile is a size a person can read. The
latest feed is everything anyone wrote, so a day away is hundreds of posts, and
"scroll past them to clear them" at that size is a joke — which is why everyone
pressed "mark all as read", the button the reading rule was meant to make
unnecessary.

So a fresh start takes the newest `unreadCatchUp` unread posts and shows the rest as
read. `capUnread` in `core/unread.dart` does it, on the first page and on the stored
page a cold start opens with; later pages spend whatever budget is left. Nothing is
sent to the server for the posts outside the set — they are read *on this device*
until the set is finished.

Finishing it is what marks the feed read. When the last post of the catch-up set is
marked, `FeedNotifier.markRead` calls `markAllRead`, which is the server's `read-all`
and therefore covers the pages the app never loaded. A reader who has caught up on
what they were offered is done, and should not have to say so.

Two consequences worth knowing:

- `FeedState.unreadCount` is the app's number, not the server's. The server counts
  everything back to your last visit; this counts what is left of what you were
  offered. `hasUnread` stays the server's, because that is what the tab dot is about.
- Ids marked read this session are re-applied to every page that arrives afterwards,
  so a revalidation behind a cold start or a pull-to-refresh cannot put a rail back
  on a post the reader has already scrolled past.

## Translation

`translation` is on the post shape: the server detects the language, translates once,
and stores nothing when the body is already English. So the app neither detects
anything nor sends anybody's post to a third-party translator — it decides whether to
offer the swap, and that is all.

Two conditions before the button appears. The setting is on, and the translation
actually differs from the body — the translator sometimes hands back its input, and a
button that swaps a body for itself is worse than no button. The rendered body is
keyed on which text is showing, so a revealed spoiler or redaction is not carried
across into different words where it would make no sense.

## Notifications

**There is no push endpoint an app can reach.** textlog does have push, but it is Web
Push: the subscription routes live under `/account/`, authenticate with a *session
cookie* rather than a bearer token, and expect a browser push endpoint with its own key
pair. A Flutter app can satisfy none of those. Instant delivery would need something
under `/api/v1/` that takes an FCM or APNs device token — the same shape of gap the
write endpoints used to be.

So the app polls `/activities/to-me`, which returns exactly replies, mentions and
follows of you, and raises the notifications itself. The cost is latency: Android will
not run periodic work more often than every fifteen minutes, and iOS decides for itself
when a background refresh is worth the battery. The setting says so rather than implying
otherwise.

Nothing is scheduled and no permission is asked for until the reader turns it on.

### The part that is easy to get wrong

Deciding *what* to say lives in `core/notification_plan.dart`, pure and tested. A poll
sees the same page of activity every fifteen minutes, so "have I already said this" is
the whole problem — and it is compared against a remembered set of activity ids rather
than a high-water mark, because those ids are opaque strings the server orders by time.
There is no "greater than" to compare.

Two details that only a device would have shown:

- **A notification action runs in a fresh isolate** that never executed `main`. Anything
  the app wired at launch is simply absent, so the entry point has to do the work
  itself — a mutable hook set from `main` is a quick reply that silently posts nothing.
- **The plugin uses the foreground callback when the app is alive** and the background
  one when it is not. Both now run the same handler; wiring only one gives you a reply
  button that works in exactly one of the two states.

`android/app/src/main/AndroidManifest.xml` declares
`com.dexterous.flutterlocalnotifications.ActionBroadcastReceiver`. The plugin ships that
class but does not declare it, and without the declaration the broadcast goes nowhere:
the shade shows a spinner forever and the reply is dropped.

### What was verified, and where

Driven on an Android emulator: the notification and its group summary appear, `Reply`
opens an inline field and posts `POST /api/v1/posts` with the right `parent_id` and
bearer token, `Mark read` posts to `/activities/to-me/read`, and the periodic job
registers with a network constraint about fifteen minutes out.

**iOS is written but unverified** — no iOS SDK on the machine this was built on. The
`Info.plist` background modes, the `BGTaskScheduler` identifier and the `AppDelegate`
registration are all in place and the identifiers match what the plugin uses, but nobody
has watched a notification arrive on a phone.

## Where the app deliberately differs from the site

Following the site is the default, and every departure is commented at the point it happens.
The list lives in [ROADMAP.md](ROADMAP.md#where-the-app-deliberately-differs-from-the-site);
the short version is that a phone needs a thumb-sized tap target, a tighter reply indent, a
flat thread view, a reading measure on a wide window, and a tab row that scrolls.

## Barebones mode

`Chrome` is a second `ThemeExtension` next to `Palette`, carrying `plain` and a text `scale`.
It rides in the theme rather than being read from settings at each call site, so a plain
`StatelessWidget` deep in the tree can ask `context.chrome.plain` without being handed a ref.

Every icon in the app goes through `Glyph(icon, plain)`, so there is one place that decides
whether you get an `Icon` or a character. Buttons, switches and spinners branch the same way.

One wrinkle worth knowing: a `ThemeExtension`'s `lerp` is not consulted at `t == 0` —
`Tween.transform` short-circuits and returns the old value — so a theme swap always costs an
animation frame. Barebones therefore also sets `themeAnimationDuration` to zero, which is
the behaviour that mode wants regardless.
