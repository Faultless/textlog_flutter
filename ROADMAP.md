# Roadmap

## Where we are — v0.0.1

| Area | State |
|---|---|
| Feeds (latest, hot) | native, paginated |
| Live firehose | native, SSE |
| Threads, profiles, tag feeds | native |
| Quoted parent posts | native |
| Reply / write | web view onto textlog.cc |
| Log in / sign up | web view onto textlog.cc |
| Follow, block, report | not in the app — web view only |
| Your own profile, activity, for-you | not in the app |
| Markdown | not rendered (neither does the site) |

## The one thing that gates the rest

textlog's public API is **read-only**. Every endpoint is `GET`/`HEAD`, there is no
authentication, and there are no mutation endpoints. Accounts and writing exist only as
session-cookie HTML form POSTs against unversioned routes.

So the roadmap splits cleanly in two:

- **Track A — things we can build now**, by pairing native reading with a web view that
  owns the session cookie.
- **Track B — things that need the server first.** Listed at the bottom so it is obvious
  what is our work and what is not.

---

## v0.0.2 — read polish

**Basic markdown (read only).**
Worth being deliberate here. The server escapes everything except URLs, `@mentions` and
`#hashtags`, and renders bodies as pre-wrapped plain text — so `**bold**` on textlog.cc
shows up as literal asterisks. If the app renders it as bold, the app is showing formatting
the author did not get, and the same post looks different in two places.

Recommended shape:
- Add inline `**bold**`, `*italic*`, `` `code` `` and `> quote` to the existing tokenizer
  in `core/body_tokens.dart` — it already returns a token list, so this is a new token
  type and a new span style, not a new rendering pipeline.
- Ship it behind a setting, **defaulted to off**, labelled as "render markdown (textlog.cc
  shows this as plain text)". Honest about the divergence, and the default matches the web.
- Do not add block-level markdown (headings, lists, tables). Posts are 280 characters;
  block layout is not what is missing.

**Other read polish**
- Share a post / profile via the system share sheet.
- Open a post's own permalink in the web view rather than an external browser.
- `ref.keepAlive()` with a disposal timer so feeds survive navigation instead of refetching.

---

## v0.1.0 — accounts, as far as the API allows

The web view already holds a real session cookie after login. That cookie is the hook for
making the app feel signed-in without inventing an auth layer.

**Know whether you are logged in.**
Read the `textlog` session cookie out of the web view's cookie jar on return. That alone
unlocks the UI below.

**Your profile.**
Once the handle is known, the profile screen is already built — point it at your own
handle. Everything on it comes from the public API, so no new data work.

**Signed-in affordances.**
- Show `reply` / `write` as active rather than always sending you to a login wall.
- A "you" entry in the app bar linking to your profile.
- Log out — clear the web view cookie jar.

**Follow / unfollow, block, report.**
Web view, one screen deep, returning to where you were. Same helper as `openReply`.

⚠️ **Deliberately not doing:** scraping textlog.cc's HTML with the session cookie to build
native `for-you`, `activity`, `followers` or `following` screens. Those pages are HTML-only
with no API equivalent. Parsing them would mean the app breaks on any markup change on the
server, which is exactly the fragility this project avoided on day one.

---

## v0.2.0 — distribution

- Split-ABI APKs (~17MB each instead of one 49MB universal file).
- A real signing key, so updates install over previous versions.
- GitHub Actions building the APK on tag push and attaching it to the release.
- App icon (currently the Flutter default).

---

## v1.0.0 — native writes — **blocked on the server**

Everything here needs textlog to add authenticated mutation endpoints. From
[post 274](https://textlog.cc/post/274), the author is open to it but wary of inviting
bots. Nothing in this app should try to route around that.

What would unblock a fully native client:

| Needed endpoint | Unlocks |
|---|---|
| token issue / refresh | native login, no web view |
| `POST /api/v1/posts` | native compose |
| `POST /api/v1/posts/{id}/replies` | native reply |
| `POST /api/v1/users/{handle}/follow` | native follow |
| `GET /api/v1/me` | your profile, settings |
| `GET /api/v1/feeds/for-you`, `/activity` | personalised feeds, notifications |

When they land, the change is contained: add the calls to `data/api.dart` and the
notifiers to `state/`. The layering means nothing above `data/` currently assumes
read-only, so the reader does not get rewritten.

Until then the web view is not a stopgap to apologise for — it is the correct answer.
It reuses the server's own login, rate limiting and moderation instead of reimplementing
them, and it cannot drift out of sync with the site.
