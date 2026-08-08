# Roadmap

## Where we are — v0.0.5

| Area | State |
|---|---|
| Feeds (latest, hot) | native, paginated |
| Live firehose | native, SSE |
| Threads | native, nested 5 deep, cached |
| Profiles, tag feeds | native |
| Quoted parent posts | native |
| Reply / write | browser tab onto textlog.cc |
| Log in / sign up | browser tab onto textlog.cc |
| Follow, block, report | not in the app |
| Your own profile | native, from your handle |
| Activity, for-you | not in the app |
| Markdown | opt-in, off by default |
| Themes | light, dark, sepia, dracula + accent |

## The one thing that gates the rest

textlog's public API is **read-only**. Every endpoint is `GET`/`HEAD`, there is no
authentication, and there are no mutation endpoints. Accounts and writing exist only as
session-cookie HTML form POSTs against unversioned routes.

So the roadmap splits cleanly in two:

- **Track A — things we can build now**, by pairing native reading with a browser tab that
  shares the system browser's session.
- **Track B — things that need the server first.** Listed at the bottom so it is obvious
  what is our work and what is not.

---

## v0.0.6 — read polish

**Done in v0.0.3:** markdown (bold, italic, strikethrough, links, bullets, headings) behind
an off-by-default setting; light / dark / sepia / dracula themes with a chosen accent.

**Done in v0.0.5:** reply pages cached for the session, so reopening a thread or following a
"+ N more replies" link costs no requests at all.

**Still to do**
- Inline `code` and `> quote` spans, the two markdown pieces left out.
- Share a post / profile via the system share sheet.
- Open a post's own permalink in a browser tab rather than handing off to the browser app.
- `ref.keepAlive()` with a disposal timer so feeds survive navigation instead of refetching.

---

## v0.1.0 — accounts, as far as the API allows

**Done in v0.0.3:** the app asks for your handle once, stores it locally, and uses the
public API for everything else. `@handle` in the app bar, your own profile with `account`
and `log out`. This is identity, not authentication — see
[ARCHITECTURE.md](ARCHITECTURE.md#accounts-identity-not-authentication).

**Still to do here**
- Follow / unfollow, block, report — browser tab, same helper as `openReply`.
- Show `reply` / `write` differently before you have introduced yourself.

⚠️ **Deliberately not doing:** scraping textlog.cc's HTML with the session cookie to build
native `for-you`, `activity`, `followers` or `following` screens. Those pages are HTML-only
with no API equivalent. Parsing them would mean the app breaks on any markup change on the
server, which is exactly the fragility this project avoided on day one.

### Why the app cannot just take over the magic link

Worth writing down, because it looks like an easy win.

`/enter/magic` deletes the token inside the same transaction that creates the session, so
it is strictly single-use — and `issueMagicLink` runs
`DELETE FROM magic_links WHERE email=?` before inserting, so requesting a second link
invalidates the first. One link, one session, one place.

If the app registered as a handler for that URL, it would claim the session and leave your
**browser** logged out — while writing still has to happen in the browser. You would be
signed in exactly where you cannot post.

The ordering therefore matters: **write endpoints first, magic-link takeover second.** Once
the app can post natively it no longer needs a browser session, and intercepting the link
breaks nothing. Doing it in the other order strands you.

---

## v0.2.0 — distribution

**Done in v0.0.4:** a real signing key, split-ABI APKs (~15–18MB against 48MB universal),
and the caret app icon.

**Still to do**
- GitHub Actions building the APKs on tag push and attaching them to the release.
- iOS. Blocked twice over: the Xcode iOS platform SDK has to be installed to build at all,
  and an unsigned build needs the recipient to sideload it with their own Apple ID. The App
  Store is out while the project is AGPL.

---

## v1.0.0 — native writes — **blocked on the server**

Everything here needs textlog to add authenticated mutation endpoints. From
[post 274](https://textlog.cc/post/274), the author is open to it but wary of inviting
bots. Nothing in this app should try to route around that.

What would unblock a fully native client:

| Needed endpoint | Unlocks |
|---|---|
| token issue / refresh | native login, no browser hand-off |
| `POST /api/v1/posts` | native compose |
| `POST /api/v1/posts/{id}/replies` | native reply |
| `POST /api/v1/users/{handle}/follow` | native follow |
| `GET /api/v1/me` | your profile, settings |
| `GET /api/v1/feeds/for-you`, `/activity` | personalised feeds, notifications |

When they land, the change is contained: add the calls to `data/api.dart` and the
notifiers to `state/`. The layering means nothing above `data/` currently assumes
read-only, so the reader does not get rewritten.

Until then the browser tab is not a stopgap to apologise for — it is the correct answer.
It reuses the server's own login, rate limiting and moderation instead of reimplementing
them, and it cannot drift out of sync with the site.
