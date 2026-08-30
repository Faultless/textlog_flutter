# Packaging for F-Droid

`dev.serge.textlog.yml` is the recipe to paste into an [fdroiddata](https://gitlab.com/fdroid/fdroiddata)
merge request as `metadata/dev.serge.textlog.yml`. It lives here so it is versioned
with the app it builds: a new Flutter version or a moved output path breaks it, and
that should be visible in the same commit that caused it.

**It has not been submitted yet**, but the decision it was waiting on has been taken:
**reproducible builds**. F-Droid rebuilds from the recipe, compares the result with
the APK attached to the GitHub release, and publishes *ours*. Same signature, so
anyone already running a build from GitHub Releases updates in place instead of having
to uninstall and lose their settings and their session. See
[Reproducible builds](#reproducible-builds-what-it-takes) for what that costs.

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

## The recipe has never been run

`fdroid build` needs their Docker environment (~5GB) or a pipeline on an fdroiddata
fork. Until one of those has produced an APK, treat every line as a hypothesis. The
parts most likely to be wrong:

- `ndk: r28c` has to match whatever the pinned Flutter resolves to.
- `srclibs: [flutter@stable]` then checking out an exact version assumes that version
  is reachable from the `stable` branch.
- The 2-hour default build timeout has to cover cloning the Flutter SDK, resolving
  pub, and a release build.

## Reproducible builds: what it takes

By default F-Droid signs with **its own key**, generated per app, and that is a
one-way door: Android refuses an in-place upgrade across a signature change, so every
existing reader would have to uninstall — losing their settings and their session —
and per F-Droid's documentation you cannot switch afterwards. That is why this app
goes the other way, and why the recipe carries `binary:` and `AllowedAPKSigningKeys`.

The price is that our APK and F-Droid's rebuild have to come out **byte for byte
identical apart from the signature**. Two things make that hard for a Flutter app, and
`build-release.sh` beside this file exists for both:

- **The toolchain.** Release builds happen inside F-Droid's own buildserver image
  (`registry.gitlab.com/fdroid/fdroidserver:buildserver`, x86_64, emulated on an arm
  Mac), not on whatever a laptop has installed. The Flutter version is the one pinned
  in `.github/workflows/pages.yml`, which is where the recipe reads it from too.
- **The path.** Flutter compiles absolute source paths into `libapp.so`, so a build
  under `/Users/someone/` cannot match one under `/home/…`. Both sides build in
  **`/home/runner/work/textlog_flutter/textlog_flutter`** — GitHub Actions' own
  workspace layout, so these builds can move into CI later without breaking anything.
  The recipe's `prebuild` and `build` do the `mv` dance to get there and back. **That
  path must never change**: changing it breaks verification for every release after.

So cutting a release is now `fdroid/build-release.sh v0.7.0`, attaching what lands in
`fdroid/out/` to the GitHub release, and pointing the recipe's `commit:` at the tag.

One trap that does not apply here: `apksigner` from build-tools 35+ produces APKs
whose signature block F-Droid's copying tool cannot handle. These APKs are signed by
AGP during the Gradle build, inside that same image, so there is no separate signing
step to pin to an older build-tools.

Per-ABI rather than one universal APK, unlike the first draft of this recipe. Flutter
offsets the versionCode itself — 1000 for `armeabi-v7a`, 2000 for `arm64-v8a`, on top
of the `+23` in pubspec — so the recipe mirrors that in `VercodeOperation`. It is two
build entries instead of one, and it saves every reader two thirds of the download.

## Submitting

1. `fdroid/build-release.sh <tag>`, and attach `fdroid/out/*.apk` to that release.
2. Point `commit:`, `versionName`, `versionCode` and `CurrentVersion*` at the tag.
3. `fdroid lint dev.serge.textlog` inside an fdroiddata checkout — it catches the
   metadata mistakes their CI would bounce anyway. (`AntiFeatures: []` and the old
   category names were both caught this way.)
4. Fork [fdroiddata](https://gitlab.com/fdroid/fdroiddata), copy the recipe to
   `metadata/dev.serge.textlog.yml`, commit as `New app: textlog`, push the branch and
   open a merge request. Their CI builds it and reports whether the rebuild matched;
   a mismatch is a comment on the MR rather than an accepted build with the wrong
   signature, so the one-way door stays shut until it passes.

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
