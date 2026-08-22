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
         models, FeedSource, body tokenizer, block markdown, polls, post context,
         SSE parser, relative time, the TLD table the autolinker needs.
data/    the only code that talks to the network. api.dart + firehose transports.
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
  LaTeX, `[label](url)`, `~strikethrough~` (one tilde, not just two), bare and schemeless
  URLs, mentions, hashtags, spoilers, and polls.
- **Behind the `markdown` setting**, because the site keeps a post body flat: headings,
  emphasis, ordered and unordered lists, task lists, blockquotes, tables and rules.

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
the options render as ordinary text. Voting is not in the API, so an option opens the post
on textlog.cc rather than pretending.

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

## Writes

`ui/widgets/compose_sheet.dart` is one form for posting, replying and editing, because on
textlog those are the same 280 characters and the same button. `ui/widgets/post_actions.dart`
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

- **Link previews and images.** The server stores and renders both; neither is on the API's
  post shape, so the app cannot show them without scraping markup.
- **Voting in a poll.** No poll endpoint in the public API — the site votes by form POST.
  The poll is shown; an option opens the post on textlog.cc.
- **A truncated following list.** `Relationships` walks at most five pages, and an account
  missing from a truncated list is reported as *unknown* rather than absent — so a follow
  button says `follow` without the arrow instead of claiming you do not follow someone you
  do. Acting on an account settles it either way.
- **A thread wider or deeper than one page.** 100 posts at depth 5 covers virtually
  everything; past that, branches advertise what is missing.

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
