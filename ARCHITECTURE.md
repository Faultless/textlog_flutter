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

Two things survive from the old shape, and neither is a workaround:

- **Signing up is still a browser tab.** The API refuses to create accounts, deliberately.
  That is where the server puts its abuse controls, and an app that routed around them would
  be the thing everyone was worried about.
- **The layering held.** Adding writes touched `data/api.dart` and added `state/session.dart`.
  Nothing in the reader assumed read-only, so nothing in the reader changed.

## Layers

Dependencies point one way only — `ui` → `state` → `data` → `core`.

```
core/    pure Dart. No Flutter, no I/O, no packages.
         models, FeedSource, body tokenizer, SSE parser, relative time.
data/    the only code that talks to the network. api.dart + firehose transports.
state/   Riverpod providers. Thin — they wire data into the widget tree. Session lives here.
ui/      widgets. Pure functions of state.
```

`core/` has no Flutter import, so every rule that decides what the user sees — how a body
is tokenized, what `3mo` means, which URL a feed maps to — is testable without a widget
tree or a server. That is most of `test/core_test.dart`, and it runs in milliseconds.

## The keystone: `FeedSource`

Every scrollable list in the app is one of five sources:

```dart
sealed class FeedSource {}
  LatestFeed()          -> feeds/latest
  HotFeed()             -> feeds/hot
  UserFeed(handle)      -> users/{handle}/posts
  TagFeed(tag)          -> tags/{tag}/posts
  RepliesFeed(postId)   -> posts/{id}/replies
```

The server returns the same envelope for all five, so one notifier
(`state/feed.dart`) and one widget (`ui/widgets/feed_view.dart`) serve every feed —
pagination, pull-to-refresh, empty states and error recovery included.

**To add a sixth feed:** add the class, add its case to `pathOf`, done. The exhaustive
`switch` in `pathOf` means the compiler tells you if you forget. No new notifier, no new
list widget, no new error handling.

`FeedSource` implements `==`/`hashCode` because it is a Riverpod family key — two
`TagFeed('dart')` values must resolve to the same cached provider.

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

## Markdown

Off by default, and that default is the point: textlog escapes everything except URLs,
mentions and hashtags, so `**bold**` really is asterisks on the site. Rendering it here
means showing formatting the author never got, and the setting says so in as many words.

`core/markdown.dart` layers on the plain tokenizer rather than replacing it. A line is
classified (heading / bullet / paragraph), markdown links are pulled out **first** — else
the plain tokenizer would link the bare URL inside `[label](url)` and lose the label — and
whatever stays plain is then scanned for emphasis. That ordering is why `**@someone**` still
resolves to a mention.

Scope is deliberately small: bold, italic, strikethrough, links, bullets, headings. No
nesting, no tables, no code fences. A test asserts that both paths link the same mentions,
tags and URLs, so turning the setting on can never lose the behaviour the site has.

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

Routes mirror the website (`/`, `/hot`, `/live`, `/post/:id`, `/u/:handle`, `/tag/:tag`),
so on web every screen has a shareable URL and "open on textlog.cc" is a straight
passthrough.

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

`/posts/{id}/replies` returns **direct children only** — every item comes back with
`parent_id` equal to the id you asked for. A nested thread is therefore assembled from one
request per branching node; the data is not already there for free.

What makes that affordable is `reply_count`: every post says how many replies it has, so we
know which nodes are worth a request and, for the ones we skip, exactly how many are still
down there. Nothing is silently dropped — an unvisited branch shows `+ N more replies`.

`state/thread.dart` walks breadth-first, fetching each level in parallel. A five-deep thread
is five round trips, not one per node in series. Two ceilings keep it bounded:
`maxThreadDepth` (5 levels, then the branch becomes a link) and `maxThreadRequests` (24, so
a very wide thread cannot make the reader wait on dozens of calls).

Assembly itself is pure — `core/reply_tree.dart` takes the fetched pages as a map and
returns the tree, so the depth cap, the budget overflow and a stale `reply_count` are all
covered by plain unit tests.

### Not spamming the replies endpoint

The server allows 120 JSON requests a minute. One thread costs a request per branching
node, so the naive version — refetch the tree every time a thread opens — rate-limits a
reader who does nothing more unusual than browsing.

`RepliesCache` holds reply pages for the whole session, keyed by the post they belong to,
outliving the provider that fetched them. It changes the arithmetic completely: reopening
a thread costs nothing, and following a `+ N more replies` link into a node the parent
thread already walked costs nothing either, because those levels are already in hand.
Measured against a real five-level thread: 10 requests cold, 0 on reopen, 0 for the
sub-thread.

Freshness is per node, not per thread, and there are three modes (`ThreadFetch`):

- **cached** — a normal open. Reuse anything held, fetch only what is missing.
- **revalidate** — the automatic pass on opening a thread that has aged past `repliesTtl`.
  Refetches only the entries that are actually stale.
- **force** — pull-to-refresh. Refetches everything.

That last one exists because the first version got it wrong: refresh ran in *revalidate*
mode, so pulling on a thread cached two minutes ago did nothing whatsoever. Someone who
pulls has usually just been told there is a new reply, and "nothing has expired yet" is
never the answer they wanted.

### Knowing a thread changed without asking

A TTL is a guess. `reply_count` is a fact, and every post carries one — feeds, the firehose
and a single-post fetch all return a current value. `RepliesCache.noticeCounts` compares it
against what we hold: if a post claims more replies than we have, our copy is provably out
of date and gets dropped, so the next read refetches. No polling, and no waiting out a TTL.

Nodes holding a full page are skipped, because there a disagreement could equally be
truncation rather than staleness.

The live stream gives a second, sharper signal. A post arriving on the firehose with a
`parent_id` says that thread changed, even though the payload carries no count for the
parent — so the parent's cached replies are dropped outright.

Stale content is shown immediately and updated behind the reader rather than replaced by a
spinner. On a micro-blog a thread that was quiet five minutes ago is almost certainly still
quiet, and being a few seconds behind costs nothing.

`fetchOnce` collapses concurrent fetches of the same node. A thread screen can build more
than once during a route transition, and without it both builds miss the cache and both hit
the network — which is exactly what the request log showed before it was added.

The rendering mirrors the site's `.reply-branch`: siblings share one hairline rail indented
by a gutter, and nodes with children carry the same `−` / `+` fold control. The fold needs
`excludeSemantics: true` or Flutter merges the label into the reply's text and the control
vanishes for screen readers.

## Quoted parents

A reply renders the post it answers in a tinted box beneath it, as the site does. The feed
endpoints return `parent_id` but not the parent, so `ParentQuote` fetches it via
`postProvider`. Riverpod caches by id, so replies sharing a parent fetch it once, and only
tiles that actually build ask for one. A quote is decoration: while it loads, or if the
parent is gone, it renders nothing rather than a spinner mid-feed.

## Known gaps

- **Explore / followers / following.** HTML-only on the server; no API equivalent.
- **Feeds refetch rather than cache across navigations.** `autoDispose` drops a feed when
  you leave it. `ref.keepAlive()` with a disposal timer in `FeedNotifier.build` is the
  standard fix if it starts to bite.
- **Reply counts on quoted parents** come from the parent fetch, so a quote can briefly
  show a count that is one behind the feed it appears in.
