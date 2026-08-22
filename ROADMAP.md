# Roadmap

## Where we are — v0.1.0

| Area | State |
|---|---|
| Feeds (latest, hot) | native, paginated |
| For you, to me | native, paginated, unread tracked, mark-read optimistic |
| Live firehose | native, SSE, gap-reconciled |
| Search | native, server side, debounced |
| Threads | native, nested 5 deep, **one request**, flat/tree toggle |
| Profiles | notes, replies, following, followers, followed hashtags |
| Hashtags | feed, counts, followers |
| Blocks | block, unblock, and a list you can undo from |
| Quoted parents | inlined by the server — no request |
| Post, reply, edit, delete | native |
| Log in | native, emailed code |
| Follow, report | native |
| Bio | native, `PATCH /me` |
| Sign up | browser tab onto textlog.cc, on purpose |
| Filter a loaded timeline | native, client-side |
| Bodies | code, fences, LaTeX, markdown links, strikethrough, spoilers, polls, ASCII art |
| Block markdown | opt-in: headings, lists, task lists, tables, quotes, rules |
| Fonts | JetBrains Mono, Fira Code or system, four sizes |
| Themes | light, dark, sepia, dracula + accent |
| Barebones mode | characters instead of icons, no ripples, no animation |

---

## v0.1.0 — catching up with the server

textlog's API grew a great deal, and most of what this app could not do, it could not do
because the endpoint did not exist. The four rows the previous roadmap listed as blocked on
the server are all shipped:

| Endpoint that appeared | What it unlocked |
|---|---|
| `GET /api/v1/activities/for-you` | the personalised feed |
| `GET /api/v1/activities/to-me` | replies and mentions of you |
| `GET /api/v1/users/{h}/followers`, `/following/users` | who follows whom |
| `GET /api/v1/users/{h}/blocks` | a block list you can undo from |

…along with `search`, `users/{h}/notes` and `/replies` as separate feeds, `tags/{t}` and its
followers, `users/{h}/following/tags`, and `PATCH /me` for a bio.

**Two fields changed how the app fetches, which matters more than any screen:**

- Every post now carries its quoted `parent`. A feed of fifty replies used to cost
  fifty-one requests — the feed, then one per quote on screen. It costs one.
- `/posts/{id}/replies` takes `depth=1..20` and returns the whole subtree flat, each reply
  carrying its own `depth`. Opening a thread used to walk it a level at a time, up to eight
  requests. It is one.

**Presentation caught up too.** The site stopped labelling posts with a bare timestamp and
started labelling them in words — `@alice replied to @bob:`, `you continued:`,
`created a poll:`, `… and mentioned you:` — moved the reply action to the foot of the post,
says `continue` when you are replying to yourself, and prints `(deleted account)` where a
removed account's handle would go. All of that is derivable from the inlined parent and the
`mentions` array, so it costs nothing.

**Still to do**
- Share a post or a profile through the system share sheet.
- A "first unread" jump in `for you`, which the site has.
- Polls are read-only. There is no poll endpoint in the public API — the site votes by form
  POST — so tapping an option opens the post on textlog.cc. Showing the poll at all is not
  optional: without it the option lines render as body text, which is not what the author
  wrote.

⚠️ **Deliberately not doing:** scraping textlog.cc's HTML for anything the API does not
serve. Parsing markup means the app breaks on any markup change on the server, which is
exactly the fragility this project avoided on day one.

---

## Where the app deliberately differs from the site

Following the site is the default. These are the places where a phone asks for something
else, and each is a decision rather than an omission:

| The site | The app | Why |
|---|---|---|
| A `read` link where the timestamp was | the relative stamp, in the same place, doing the same thing | On a dense phone feed the time is the most useful thing on the line, and it costs the same room |
| Tree threads only | a `flat` toggle, and a tighter indent under 420px | Five levels of a full gutter is a quarter of a 390px screen before a word is drawn |
| Mouse-sized text links | every link padded to a thumb-sized hit box | Measured: 29 of 33 tap targets were 16px tall |
| Three feed tabs | five, in a row that scrolls | `live` has no web equivalent, and a clipped tab row is a row with unreachable tabs |
| Followed-hashtag count on a profile | a `tags` tab listing them | The endpoint exists and on a phone that list is a good way to get around |
| No floating action button | one, except in barebones mode | It is the one place a phone convention beats the site's |

## Barebones mode

An opt-in mode that takes the app back to the site's own vocabulary: icons become `<`, `/`,
`=`, `+` and `…`; filled buttons become `[ label ]`; switches become `[x]`; spinners say
`loading…`; selection reads `[*] dark`; and nothing ripples, slides or crossfades.

Pull-to-refresh stays. It is a gesture rather than chrome, and removing a standard mobile
affordance would make the app worse rather than more spartan.

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

## v1.0.0 — what is still thinner than the site

Not blocked on the server any more; just not built yet.

- Link previews and images. The server stores both and renders them, but neither is on the
  API's post shape, so the app cannot show them without scraping.
- Voting in a poll, per above.
- Admin and moderation views. The site has them behind `isAdmin`; the API does not expose
  them, and a mobile client is not where they belong.
