# Architecture

How this client is put together and why. For what it is and how to run it, see the
[README](README.md); for what is planned, the [roadmap](ROADMAP.md).

## The constraint that shapes everything

textlog's public API is **read-only**: `GET`/`HEAD` only, no authentication, `CORS: *`.
Posting, replying, following and logging in exist solely as session-cookie HTML form
POSTs against unversioned routes. The author's position, from
[post 274](https://textlog.cc/post/274):

> if someone wants to implement API authentication and mutation endpoints they are free to try

So the app reads natively and hands every write to textlog.cc itself, in an in-app web
view that owns the session cookie (`ui/screens/web_action.dart`). Replying, posting and
logging in work exactly as they do in a browser, and the cookie survives between launches.
That is not a limitation we work around — it is the reason the whole thing has no auth
code, no token storage, no offline write queue and no sync conflicts.

If mutation endpoints ever land, the place to add them is `data/api.dart`; nothing above
it assumes read-only.

## Layers

Dependencies point one way only — `ui` → `state` → `data` → `core`.

```
core/    pure Dart. No Flutter, no I/O, no packages.
         models, FeedSource, body tokenizer, SSE parser, relative time.
data/    the only code that talks to the network. api.dart + firehose transports.
state/   Riverpod providers. Thin — they wire data into the widget tree.
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

## Visual identity

Colours in `ui/theme.dart` are textlog's CSS custom properties copied verbatim and kept
under their original names (`--soft` → `Palette.soft`), so a change on the site is a
one-line diff here. Same for the `--space-*` scale and `--gutter`'s `clamp(18px, 3vw, 28px)`.

Two details that carry most of the look: everything is monospace, and links are
accent-coloured with an underline in a *quieter* colour (`linkBorder`) — that is what
stops a dense feed reading as a wall of green.

The body tokenizer in `core/body_tokens.dart` is a direct port of the server's `linkify`
(`src/utils.ts`), including the rule that trailing sentence punctuation stays outside a
URL. Bodies render identically to the website.

## Live tab

`/api/v1/firehose` is an SSE stream of every new post. `package:http` buffers whole
responses in the browser, so the transport is conditionally imported — a streamed request
on mobile, native `EventSource` on web — while the parser (`core/sse.dart`) is shared and
pure. Reconnects with exponential backoff; the server allows three streams per IP.

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

`openReply` and `openCompose` push a web view onto textlog.cc — `/post/{id}?reply=1` and
`/write`. Navigation is pinned to the textlog origin; anything else is handed to the real
browser, so this never becomes a general-purpose web view. On Flutter web there is no
web view plugin, and a new tab is the native equivalent, so it opens one.

When the view closes, the caches that would still show pre-write state are invalidated.

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
