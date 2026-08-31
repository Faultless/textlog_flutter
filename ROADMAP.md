# Roadmap

## Where we are — v0.7.2

| Area | State |
|---|---|
| Feeds (all, hot) | native, paginated |
| My feed, @ | native, paginated, unread tracked, mark-read optimistic |
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
| Bodies | code, fences, LaTeX, markdown links, bold, underline, italics, strikethrough, redactions, quotes, spoilers, ASCII art |
| Block markdown | opt-in: headings, lists, task lists, tables, quotes, rules |
| Fonts | JetBrains Mono, Fira Code or system, four sizes |
| Themes | light, dark, sepia, dracula + accent |
| Barebones mode | characters instead of icons, no ripples, no animation |
| Feeds | replies join their parent on the page, so a conversation is not repeated |
| Notifications | replies, mentions and follows; quick reply and mark-read from the shade |
| Activity | marks itself read as a row comes into view, not only on tap |
| Latest feed | read as you, a dozen posts at a time; finishing them clears the rest |
| Bookmarks | keep a post, and a list of what you kept, shared with the website |
| `#exec` | the output the server got when it ran the code, under the code |
| `#map` | the place the server geocoded, as a card that opens your maps app |
| `#pin` | a pinned note and reply, above the profile's list rather than lost in it |
| Code fences | `js` and `python` coloured, the way the site colours them |
| Cold start | signed in and showing the last feed before anything loads |
| Reading prefs | tab order and visibility, timestamps, reply counts, follow notices |
| Gestures | swipe a post to reply |
| Translation | the server's, offered on a post it found was not English |
| Drafts | server-side, shared with the website; a post can be moved back to one |
| Polls | real options and tally from the API, and voting |
| Quizzes | `#quiz`, the marked answer, the verdict and the explanation |
| Link previews | thumbnail and text, or compact text where there is no image |
| Checklists | `#todo` lists, ticked by the author |
| Drafts | server-side, shared with the website |
| Explore | people and hashtags to follow |
| Hashtags | follow and block, as well as read |
| Links to textlog | opened in the app — posts, profiles, hashtags, feeds |
| Locked threads | `#lock` said before a reply is written, and the 409 handled |
| Voice clips | played in place, streamed through textlog's own proxy |

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

## v0.7.2 — what F-Droid review asked for

Two changes, neither of them visible in the app.

**Per-ABI version codes on F-Droid's scheme.** Flutter offsets a split build's code by
1000 for `armeabi-v7a` and 2000 for `arm64-v8a`, which leaves holes in the hundreds and
sorts strangely against the universal build. F-Droid asks for `code * 10 + n`, so
pubspec's `+25` becomes 251 and 252 — adjacent, ordered, and the same scheme their
other Flutter apps use. Done in `build.gradle.kts` with the snippet from the review on
[fdroiddata!47312](https://gitlab.com/fdroid/fdroiddata/-/merge_requests/47312).

**No dependency metadata in the signature.** The Android Gradle Plugin writes a signed
blob listing the app's dependencies into the APK signing block, for the Play Store to
read. F-Droid's scanner rejects an APK carrying a signing block it cannot account for,
which is the right call, and nothing here wanted Google reading a dependency list
either. `dependenciesInfo { includeInApk = false }`.

---

## v0.7.1 — buildable by F-Droid

One line, and no change anyone can see. F-Droid builds from source, and before it
builds it strips signing configuration out of `build.gradle.kts` with a line-based
rule: `signingConfig = <something with no spaces>`. This app's release signing config
was written across two lines, so the rule deleted the first and left the `?:`
continuation behind — their build could not compile the file at all. It is one line
now, which the rule does not match, and the fallback to the debug key that F-Droid
wants happens by itself once the `signingConfigs` block above it is removed.

Found by running `fdroid build` against the recipe for the first time rather than by
reading the documentation, which is also how three metadata errors and a pair of `rm:`
globs pointing at directories this repo has never had came to light. See
[fdroid/README.md](fdroid/README.md).

---

## v0.7.0 — read by reading, and caught up with the server

**Reading a post is now what marks it read.** Three things were wrong with the old
rule and each of them left dots on screen that the reader had earned the right to be
rid of:

- A post had to be *fully* inside the viewport. The post filling the screen was never
  fully inside it, and neither was the one you had plainly started at the bottom
  edge — so the ones you actually read were the ones that stayed unread. Now a slice
  of a post showing is enough, and the only thing excluded is the hairline of the next
  one always poking in at the edge.
- Nothing was marked until the scroll *stopped*. Now every scroll notification sweeps,
  and the ids are batched behind it — so a fling through forty posts is still one
  request, and the rails go as they pass.
- A reply grouped under a post on the same page was never marked at all, because only
  the top of each block was measured. Passing the block passes everything in it.

**And a backlog you can finish.** The latest feed is everything anyone wrote, so a day
away means hundreds unread — and a rule that says "scroll past it to clear it" is a
joke at that size, which is why everyone pressed "mark all as read" instead. A fresh
start now offers a **catch-up set of a dozen posts**: the newest ones, marked unread,
with everything behind them shown as read. Read those twelve and the app marks the
whole feed read on the server, pages it never loaded included. The button is still
there; it should just never be the only way out.

**Caught up with upstream**, which had moved a long way:

- **Bookmarks.** Keep a post from its menu, and `/bookmarks` lists what you kept —
  server side, so it is the same collection as the website's.
- **`#exec`.** The server runs the code fence once, when the post is written, and
  stores what it printed. The output is drawn under the post, clipped to the same ten
  lines and two hundred characters a line the site clips it to. Nothing executes on
  the phone.
- **`#map`.** The server geocodes the place and renders the tile itself, so the card
  is a picture from textlog and a link to whichever maps site it picked. The reader's
  own location is never involved.
- **`#pin`.** A profile's pinned note and pinned reply come back on the profile, so
  they are drawn above the list and left out of it rather than sitting in date order.
- **Coloured code fences.** `js` and `python`, in the four colours the site's
  stylesheet gives them. A hundred lines of scanner rather than a highlighting
  library: it cannot fail on code it does not understand, and the worst it does is
  leave a run plain.
- **The site's new names.** `to me` is `@`, `for you` is `my feed`, `latest` is `all`,
  and `@` goes first, as it does on the web. Links to the old URLs still open in the
  app — the site redirects them, and so does the app's own link table.

The endpoints keep their old spellings on purpose: `/feeds/latest` and
`/activities/for-you` are documented as backward-compatible aliases of `/feeds/all`
and `/activities/my-feed`, which means the old names work against every server the app
might meet and the new ones only work against a new one.

Still upstream-only: the `conversations` feeds — the app groups a page into threads
itself, and has since v0.2.0 — and moderation flags.

---

## v0.6.0 — opens as itself, and yours to arrange

**The app opens as itself.** A cold start used to render signed out and then rearrange
itself once storage and a network round trip had answered. Storage is opened before
the first frame, the stored session is what the UI reads until the real one lands, and
the last page of `hot` and `latest` is kept on disk so there are posts on screen
immediately. Confirmation happens behind the reader; only a rejected token signs
anyone out.

**Reading preferences.** Reorder or hide tabs, turn timestamps or reply counts off,
keep follow notices out of `for you`, and swipe a post leftwards to reply. All
persisted, all defaulting to how the app shipped.

**Translation**, from the server rather than from anywhere else: textlog detects the
language and translates once per post, so the app only decides whether to offer the
swap.

**Caught up with upstream:** a post can be **moved back to drafts** now that there is
an API route for it, and the **latest feed is read as you** — which brings unread
marks that clear as you scroll, a mark-all, and, less visibly, feeds that actually
apply the accounts and hashtags you blocked. They did not before, because feed reads
went out anonymously.

Still upstream-only: moderation flags and `direct_reply_count`, both on the website's
post shape rather than the API's.

---

## v0.5.0 — clips that play, and dots that clear themselves

**Voice clips play in the app.** They opened Vocaroo before, which was a deliberate
call and the wrong one. Streamed through textlog's own `/media/vocaroo/{id}` proxy, so
listening tells Vocaroo nothing. One player for the app, created only when a clip is
first pressed, so a feed full of them costs nothing until you press one.

**Activity marks itself read as you scroll past it.** Only a tap counted before, so
reading a whole tab left every dot in place and the only way to clear them was "mark
all as read" — a chore you had already done by reading. A row counts once it has been
*fully* on screen; half a row at the bottom edge is the thing you were scrolling
towards, not the thing you just read.

**Packaged for F-Droid**: fastlane metadata with real screenshots, a pinned Flutter
floor, and the build recipe under `fdroid/`. Not submitted — see `fdroid/README.md`
for the one decision that has to be made first, because the first accepted build
settles whose key signs it forever.

---

## v0.4.0 — catching up with the syntax, and a retry that reads as one

**A quiz took down the page it was on.** Quizzes landed upstream as polls with a right
answer, and a quiz has no deadline — so `expires_at` came back null where the app read a
required string. Every feed page, search result and thread carrying one failed to decode
whole. Quizzes now work properly: `#quiz`, the answer marked `>`, an optional explanation
after a blank line, the right answer and the explanation withheld until you commit to one,
a tick or a cross as well as a colour, no countdown, and `created a quiz` in the meta line
rather than calling it a poll.

**Three new body markers.** `/italics/` — the site had already spent `*` on bold and `_` on
underline. `|redacted|`, a bar you press to reveal, drawn ink-on-ink so revealing it does
not reflow the paragraph. And `>` quoted lines, which are *not* behind the markdown setting
because the site quotes unconditionally: consecutive lines group into one quote, `> > x`
nests, and both fenced code and ASCII art are left alone — the first so a quiz-syntax
example stays literal, the second because a drawing's first column is often `>`.

**Locked threads.** A `#lock` closes the thread under it and the server answers a reply
with `409 thread_locked`. The app now says `thread locked` where the reply link would be,
worked out from the post's own tags and the parent the API inlines, and carried down a
thread from its subject. The server still has the last word; knowing early just saves
writing a reply that was never going to be accepted.

**Voice clips** are named rather than left as a bare URL. Vocaroo sends no preview metadata
at all, so without this a clip and a blog post looked identical.

**Retry did nothing visible.** Riverpod keeps the previous error while a provider rebuilds,
so the error branch drew the same words and the same button with no spinner — tapping it
was indistinguishable from tapping nothing, which is why the only refresh that felt real
was pulling down. It says `retrying…` now and stops accepting taps until the request
settles, which meant every call site had to return a future that completes when the
refetch does rather than a bare `invalidate`. The profile screen, which had no retry at
all, has one.

Upstream also raised the read limit to **600 a minute when signed in** (from 120, and now
counted per account rather than per IP). Nothing in the app encodes the number — it reacts
to a 429 — but it is why paging a long thread signed in no longer meets the gate.

**Left alone, and why:** playing a voice clip needs an audio engine and everything that
comes with one; `#pin` already arrives in the right order from the API but the badge is not
on the API's post shape; unpublishing a post back into a draft is a website form with no
API route behind it.

---

## v0.3.1 — links that stay in the app, and taps that land

Three things, all reported from a phone rather than found in a test.

**A checklist could not be ticked.** The card underneath every item opens the post it is
about, so on the post's own page a tick pushed another copy of the page already showing —
and a second tick another. Two fixes, because there were two faults: `openPost` now
refuses to navigate to the route already on screen, and an item absorbs its own tap even
when it cannot act on it, rather than leaving `onTap: null` for the card to catch. The
subject card takes no tap at all now, so it does not offer a press that does nothing. See
"Where a tap goes" in ARCHITECTURE.md.

**A link back to textlog left the app.** `/post/2201` in a body used to open a browser onto
a page the app already had a screen for. `core/app_links.dart` maps a URL to a route —
posts, profiles, hashtags and their followers, every feed, search with its query, drafts,
and `/enter` onto the account screen. Anything else still goes to the browser, including
the cases worth being careful about: another site, a lookalike host like
`textlog.cc.example`, `/account/…` which deliberately has no screen here, and a
`javascript:` URI.

**A fenced code block blanked the page it was on.** The tinted box asked for
`width: double.infinity` inside its own sideways viewport, where the width is unbounded —
it threw during layout and the whole thread came up empty, post and replies and reply form
with it. Every post upstream with a code fence in it was an empty page. It now measures the
column outside the scroll view and asks for that as a minimum, so a short fence still fills
the width and a long one still scrolls. This is the second blank page from asking for the
whole of an unbounded axis; the first was `CrossAxisAlignment.stretch` in a link preview.

---

## v0.3.0 — everything that was waiting on the server

Every row of the "what would need the server" table from v0.2.0 is gone. textlog put all
four on the API in one go, and the app uses them:

| Was waiting on | Now |
|---|---|
| `link_previews` on the post shape | there — thumbnail beside the text, compact text where there is no image |
| a poll endpoint | `POST /posts/{id}/poll/votes`, and the poll itself is on the post |
| `/api/v1/drafts` | full CRUD and publish, so a draft crosses between web and app |
| an FCM or APNs endpoint | **still missing** — see below |

…plus `POST`/`DELETE /tags/{tag}/follow` and `/block`, and `GET /explore`.

**Checklists** are new upstream and new here: a `#todo` line and `[ ]` / `[x]` items.
There is deliberately no endpoint for ticking one — a checklist *is* the body, so a tick
is an edit, which means only its author can tick it. The same rule the site has.

**Bold and underline** are rendered unconditionally now. `*x*` is bold and `_x_` is
underline — not italics, and not behind the markdown setting. The app had them the other
way round on both counts, which meant showing the reader something the author did not
write.

**The character limit is 500**, up from 280. The bio limit was also wrong, in the other
direction: the app allowed 280 where the server caps at 160, so it accepted bios the
server then refused.

**Still to do**
- Share a post or a profile through the system share sheet.
- Group the activity feeds into threads, as the post feeds already are.
- The site's unread tracking for the latest feed (`/feeds/latest/read`).

### The one thing still waiting on the server

Instant notifications need an endpoint under `/api/v1/` that takes an FCM or APNs device
token. textlog's push is Web Push under `/account/`, cookie-authenticated, expecting a
browser endpoint — none of which an app can use. Until then the app polls, and Android
will not run periodic work more often than every fifteen minutes.

---

## v0.2.0 — notifications, and a feed that stops repeating itself

Upstream added a great deal in 54 commits, but **almost none of it to the API**: the only
new endpoint behaviour is `bot` as a report reason. Link previews and drafts both shipped
on the site and neither is on the API's post shape, so neither is implementable here.

What *was* portable is the change with the most effect on a phone: the site now joins a
reply to its parent when both are on the same feed page, instead of rendering the reply
separately with the parent quoted underneath. That is pure client-side work on data the
feed already returns — on a live page of twenty posts, six nest and six duplicated quotes
disappear.

**Notifications** are new, and the shape of them is dictated by what the server offers.
textlog's push is Web Push under `/account/`, cookie-authenticated, expecting a browser
endpoint — nothing an app can use. So the app polls `/activities/to-me` in the background
and raises the notifications itself, with a reply field and a mark-read button in the
shade. Latency is the price: fifteen minutes on Android, whenever-iOS-feels-like-it on
iOS. The setting says so.

**Still to do**
- Share a post or a profile through the system share sheet.
- Group the activity feeds into threads too. The post feeds do it now; activity rows each
  carry their own unread state and mark-read behaviour, and getting that wrong is worse
  than the duplication.
- A "first unread" jump in `for you`, which the site has.

### What would need the server

| Wanted | Needs |
|---|---|
| Instant notifications | an `/api/v1/` endpoint taking an FCM or APNs device token |
| Link previews | `link_previews` on the API's post shape |
| Drafts | `/api/v1/drafts` |
| Voting in a poll | a poll endpoint; the site votes by form POST |

Each is the same shape of gap the write endpoints were before
[stagas/textlog#3](https://github.com/stagas/textlog/pull/3), and the same answer applies:
ask for the endpoint rather than scrape the HTML.

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
