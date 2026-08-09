# Roadmap

## Where we are — v0.0.8

| Area | State |
|---|---|
| Feeds (latest, hot) | native, paginated |
| Live firehose | native, SSE, gap-reconciled |
| Threads | native, nested 5 deep, cached |
| Profiles, tag feeds | native |
| Quoted parent posts | native |
| Post, reply, edit, delete | native |
| Log in | native, emailed code |
| Follow, report | native |
| Sign up | browser tab onto textlog.cc |
| Filter a loaded timeline | native, client-side |
| Your own profile | native, from your session |
| Activity, for-you | not in the app |
| Markdown | opt-in, off by default |
| Fonts | JetBrains Mono, Fira Code or system |
| Themes | light, dark, sepia, dracula + accent |

## The thing that used to gate the rest

textlog's public API was read-only: every endpoint `GET`/`HEAD`, no authentication, no
mutations. Accounts and writing existed only as session-cookie HTML form POSTs. So this app
read natively and handed every write to a browser tab, and everything below was split into
what we could build and what needed the server first.

That is no longer the shape of the problem. textlog now ships authenticated write endpoints
([stagas/textlog#3](https://github.com/stagas/textlog/pull/3), written for this client), and
v0.0.8 uses them for everything except signing up.

---

## v0.0.6 — read polish

**Done in v0.0.3:** markdown (bold, italic, strikethrough, links, bullets, headings) behind
an off-by-default setting; light / dark / sepia / dracula themes with a chosen accent.

**Done in v0.0.5:** reply pages cached for the session, so reopening a thread or following a
"+ N more replies" link costs no requests at all.

**Still to do**
- Inline `code` and `> quote` spans, the two markdown pieces left out.
- Share a post / profile via the system share sheet.

---

## v0.0.8 — native writes

**Done:** sign in with an emailed code, post, reply, edit, delete, follow, unfollow and
report, all against the API with a bearer token. Account actions moved behind your handle in
the app bar. Timelines you have already loaded can be filtered as you type, with no request.
Edits and deletes are written into the caches that hold the post instead of refetching.

The token is an ordinary textlog session and shows up under account security on the website
like any other, so signing out there signs the app out too.

**Still to do**
- Sign up. Accounts are only ever created in a browser, on purpose: it is where the server
  puts its abuse controls, and the API deliberately refuses to be a way around them.
- Block, and a list of who you have blocked. The endpoint exists, the screen does not.
- Show `reply` and `write` differently before you have signed in.

⚠️ **Deliberately not doing:** scraping textlog.cc's HTML with the session cookie to build
native `for-you`, `activity`, `followers` or `following` screens. Those pages are HTML-only
with no API equivalent. Parsing them would mean the app breaks on any markup change on the
server, which is exactly the fragility this project avoided on day one.

---

## v0.2.0 — distribution

**Done in v0.0.4:** a real signing key, split-ABI APKs (~15–18MB against 48MB universal),
and the caret app icon.

**Done in v0.0.7:** a macOS build, and the web build deployed to GitHub Pages on every push
to `main`.

**Still to do**
- GitHub Actions building the APKs on tag push and attaching them to the release.
- iOS. Blocked twice over: the Xcode iOS platform SDK has to be installed to build at all,
  and an unsigned build needs the recipient to sideload it with their own Apple ID. The App
  Store is out while the project is AGPL.

---

## v1.0.0 — the screens that still need the server

These are the last places the app is thinner than the site, and each needs an endpoint that
does not exist yet:

| Needed endpoint | Unlocks |
|---|---|
| `GET /api/v1/feeds/for-you` | the personalised feed |
| `GET /api/v1/activity` | replies and mentions of you |
| `GET /api/v1/users/{handle}/followers`, `/following` | who follows whom |
| `GET /api/v1/me/blocks` | a block list you can undo from |

The layering means adding them stays contained: the calls go in `data/api.dart`, the
notifiers in `state/`, and the reader above them does not change.
