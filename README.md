# textlog for Android & iOS

A community-built mobile client for [textlog.cc](https://textlog.cc) — a small, text-first
place to write short notes and follow people and hashtags you care about.

The website already works fine on a phone. This exists because a community deserves a way
in that feels like it belongs on the device: native scrolling, a live feed of new posts,
threads you can follow with your thumb, and posts that look exactly like they do on the
web. Nothing more. No algorithm, no metrics, no accounts of its own.

**Unofficial.** Not affiliated with textlog.cc — see [acknowledgements](#acknowledgements).

## Install

**Android** — grab the `.apk` from [Releases](../../releases) and open it. Android will ask
once for permission to install apps from your browser or files app; that is expected for
anything not from the Play Store.

**iOS** — no builds yet. Build it yourself with the steps below.

> These are early pre-release builds signed with a debug key. They install and run, but a
> future properly-signed build will not install over them — you will need to uninstall
> first. See [RELEASING.md](RELEASING.md).

## Roadmap

Read the whole thing in [ROADMAP.md](ROADMAP.md). In short:

**Working today (v0.0.1)**
- Latest and hot feeds, infinite scroll
- Live tab — new posts stream in as they are written
- Threads with the parent post quoted, profiles, hashtag feeds
- Replying, posting and logging in, via textlog.cc in an in-app browser

**Next — read polish (v0.0.2)**
- Basic markdown for reading, off by default (textlog.cc itself shows plain text)
- Share a post or profile
- Keep feeds warm instead of refetching when you navigate back

**Then — accounts (v0.1.0)**
- Know when you are signed in, and show your own profile
- Follow, unfollow, block and report
- Log out

**Then — distribution (v0.2.0)**
- Smaller per-device APKs, a real signing key, an app icon
- Automated builds attached to each release

**Someday — fully native writing (v1.0.0)**
- Blocked on textlog adding authenticated write endpoints to its API. Until then, writing
  goes through the site itself, which is the honest answer rather than a workaround.

## Development

Needs [Flutter](https://docs.flutter.dev/get-started/install) 3.41 or newer.

```sh
git clone https://github.com/Faultless/textlog_flutter.git
cd textlog_flutter
flutter pub get

flutter run                 # a connected phone or emulator
flutter run -d chrome       # in a browser

flutter test
flutter analyze
```

## Contributing

Contributions are welcome, especially from people who actually use textlog. Issues,
suggestions and pull requests are all fine — and if you are unsure whether an idea fits,
open an issue first and let's talk about it.

Before a pull request:

- `flutter analyze` and `flutter test` both clean.
- Read [ARCHITECTURE.md](ARCHITECTURE.md). It is short, and it explains the two ideas the
  codebase leans on — pure logic in `core/`, and every feed being one `FeedSource`. New
  features are usually much smaller than they look once you know those.
- Match the surrounding style: immutable data, effects only in `data/`, and comments that
  explain *why* rather than restate the code.
- Keep the visual identity. Colours and spacing come from textlog's own stylesheet; if the
  site changes, change them here rather than inventing new values.

Please don't add tracking, analytics, ads, or anything that scrapes the site's HTML. The
first three are against the spirit of the place; the last one breaks the moment the server
changes its markup.

## Acknowledgements

textlog is designed, built and run by **[stagas](https://github.com/stagas)** —
[github.com/stagas/textlog](https://github.com/stagas/textlog). The service, its design,
and the public read-only API that makes this client possible are all their work.

This app deliberately follows the site rather than reinterpreting it: the colours are its
CSS variables, the text is its monospace, and the way bodies render is a direct port of its
own code, so a post looks the same wherever you read it.

Thanks for building somewhere worth writing.

## License

[GNU AGPL v3](LICENSE) — the same license as textlog itself.

This is not an arbitrary choice. Parts of this client are ports of textlog's AGPL-licensed
source: the body tokenizer reproduces its `linkify`, the timestamps reproduce its `fmt`,
and the palette is its stylesheet's values. A translation into another language is still a
derivative work, so a permissive license was never ours to pick on our own.

The practical effect is the one we wanted anyway: anyone can use, study, change and share
this, and improvements stay available to the community. If you distribute a modified build,
share the source too.

One consequence worth knowing: AGPL and GPL apps have historically been incompatible with
Apple's App Store terms. Distributing on iOS would mean either relicensing — which needs
sign-off from stagas for the ported parts — or replacing those parts with independent
implementations.
