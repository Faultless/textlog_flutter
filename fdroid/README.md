# Packaging for F-Droid

`dev.serge.textlog.yml` is the recipe to paste into an [fdroiddata](https://gitlab.com/fdroid/fdroiddata)
merge request as `metadata/dev.serge.textlog.yml`. It lives here so it is versioned
with the app it builds: a new Flutter version or a moved output path breaks it, and
that should be visible in the same commit that caused it.

**It has not been submitted.** Two things have to happen first, and one of them is a
decision that cannot be taken back.

## What already holds up

- **AGPL-3.0**, the same licence as textlog itself. FSF- and OSI-approved.
- **No proprietary dependency to strip.** This is the part that usually sinks a Flutter
  app: `geolocator`, `cronet_http` and friends pull Google Play Services in through
  their Android side, and the recipes for those apps are half `sed` commands deleting
  GMS out of the pub cache. Nothing here does that — `flutter_local_notifications` and
  `workmanager` both use AOSP APIs, because textlog has no push endpoint an app can
  reach and notifications are raised from a background poll instead. Verified on the
  shipped APK: zero `com.google.android.gms` or Firebase classes.
- **`pubspec.lock` is committed.** F-Droid's scanner errors on a `pubspec.yaml`
  without a lockfile beside it.
- **Tagged releases**, `vMAJOR.MINOR.PATCH`, matching `UpdateCheckMode: Tags`.
- **`version: 0.4.0+20`** in the shape `UpdateCheckData` expects, so new releases are
  picked up without editing metadata by hand.
- **A bare clone builds.** With `android/key.properties` absent — which is how their
  buildserver sees it — Gradle falls back to debug signing and
  `flutter build apk --release` still succeeds. F-Droid strips signatures and applies
  its own, so the fallback is harmless there.

## What is still open

### 1. The recipe has never been run

`fdroid build` needs their Docker environment (~5GB) or a pipeline on an fdroiddata
fork. Until one of those has produced an APK, treat every line as a hypothesis. The
parts most likely to be wrong:

- `ndk: r28c` has to match whatever the pinned Flutter resolves to.
- `srclibs: [flutter@stable]` then checking out an exact version assumes that version
  is reachable from the `stable` branch.
- The 2-hour default build timeout has to cover cloning the Flutter SDK, resolving
  pub, and a release build.

### 2. Whose key signs it — and this one is a one-way door

By default **F-Droid signs with its own key**, generated per app. The consequence is
not subtle: Android refuses an in-place upgrade across a signature change, so anyone
already running the APK from GitHub Releases would have to **uninstall first, losing
their settings and their signed-in session**, to move to the F-Droid build. And per
F-Droid's own documentation you cannot switch to the other option afterwards.

The other option is **reproducible builds**: F-Droid rebuilds from this recipe,
compares the result against the APK attached to the GitHub release, and publishes
*ours* — same signature, so an existing install updates in place. It needs
`Binaries:` and `AllowedAPKSigningKeys:` added to the recipe, and it is real work for
a Flutter app, because Flutter embeds absolute build paths into its compiled
libraries: the buildserver has to build from the identical path, which is what the
`sudo: mkdir -p /upstream/path/…` dance in F-Droid's own Flutter template is for.
There is also a known trap where `apksigner` from build-tools 35+ produces APKs their
signature-copying tool cannot verify, so release signing has to be pinned to
build-tools 34.

**Nothing should be submitted until that choice is made**, because the first accepted
build settles it.

## Fastlane metadata

`fastlane/metadata/android/en-US/` in the repo root, which F-Droid reads directly from
here — descriptions and screenshots are never taken from fdroiddata. `changelogs/`
is keyed by versionCode, so a release also needs its `<versionCode>.txt`.

Screenshots are captured from a real Android build on an emulator with SystemUI demo
mode on, so the status bar is a clean 9:00 rather than a developer's notification
tray. The wide one under `tenInchScreenshots` is the Flutter web build at 1280px,
which is the honest way to show the reading column on a tablet.

## Not F-Droid: the other two routes

- **A repo of our own** — `fdroid init`, `fdroid update`, publish `repo/` anywhere over
  HTTPS. Keeps our signing key, no review, no reproducible-build work, and a URL
  ending `/fdroid/repo?fingerprint=…` that the F-Droid client will offer to add. The
  cost is discovery: nobody finds it by browsing.
- **IzzyOnDroid** — normally the recommended stepping stone, because it lists
  developer-signed APKs without building from source. Two reasons to check before
  spending effort there: a hard ~30MB per-APK budget, which the universal build
  (57MB) exceeds and only a per-ABI split fits; and an explicit policy against apps
  written wholly or partly by generative AI tools, which this codebase would have to
  be declared under.
