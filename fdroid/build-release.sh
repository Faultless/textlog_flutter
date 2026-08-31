#!/usr/bin/env bash
# Build the release APKs the way F-Droid will rebuild them.
#
# Reproducible builds mean F-Droid rebuilds this app from the recipe, compares the
# result with the APK attached to the GitHub release, and — if they match — publishes
# *ours*, signature and all. So an existing install updates in place instead of every
# reader having to uninstall and lose their session.
#
# Matching is not automatic. Two things have to be the same on both machines:
#
#   * the toolchain — so this builds inside F-Droid's own buildserver image rather
#     than on whatever the developer's laptop happens to have installed;
#   * the absolute path — Flutter compiles source paths into libapp.so, so a build
#     under /Users/someone/ differs byte for byte from one under /home/runner/. Both
#     sides use the path in REPRO below, and it must never change.
#
# Usage:  fdroid/build-release.sh [commit]   # defaults to the tag for pubspec's version
# Output: fdroid/out/textlog-<version>-<abi>.apk, signed with the release key.
#
# The commit matters: F-Droid builds the hash named in the recipe, so this builds the
# same one rather than whatever the working tree happens to be.
set -euo pipefail

IMAGE=registry.gitlab.com/fdroid/fdroidserver:buildserver
# The path both this build and F-Droid's rebuild happen in. GitHub Actions' own
# workspace layout, so moving these builds into CI later changes nothing.
REPRO=/home/runner/work/textlog_flutter/textlog_flutter
KEYS=${KEYSTORE_DIR:-$HOME/keystores}

root=$(cd "$(dirname "$0")/.." && pwd)
version=$(sed -n -E 's/^version: ([^+]+)\+.*/\1/p' "$root/pubspec.yaml")
flutter_version=$(sed -n -E 's/.*flutter-version:[[:space:]]*([^[:space:]]+).*/\1/p' \
  "$root/.github/workflows/pages.yml")
out="$root/fdroid/out"
commit=${1:-v$version}
git -C "$root" rev-parse --verify --quiet "$commit^{commit}" >/dev/null \
  || { echo "no such commit: $commit"; exit 1; }

[[ $version && $flutter_version ]] || { echo "no version in pubspec/workflow"; exit 1; }
[[ -f $KEYS/textlog-release.jks ]] || { echo "no keystore at $KEYS"; exit 1; }

rm -rf "$out" && mkdir -p "$out"
echo "textlog $version · $(git -C "$root" rev-parse --short "$commit") · flutter $flutter_version"

# --platform: the buildserver image is x86_64, and so is the machine F-Droid rebuilds
# on. Emulated on an arm Mac, which is slow and correct.
# Named volumes for the SDK and Gradle's caches. Nothing in them reaches the APK —
# they exist so a second run does not spend a quarter of an hour re-downloading an
# Android SDK through an emulator.
docker run --rm --platform linux/amd64 \
  -v textlog-android-sdk:/opt/android-sdk -v textlog-gradle:/root/.gradle \
  -v "$root":/src:ro -v "$out":/out -v "$KEYS":/keys:ro \
  -e "REPRO=$REPRO" -e "FLUTTER_VERSION=$flutter_version" -e "VERSION=$version" \
  -e "COMMIT=$(git -C "$root" rev-parse "$commit")" \
  "$IMAGE" bash -euo pipefail -c '
    # The image ships an empty SDK — `fdroid build` installs what a recipe asks for,
    # so a build outside fdroid has to ask for the same things itself. The NDK is the
    # version this Flutter pins (r28c), which is what the recipe declares.
    export ANDROID_HOME=/opt/android-sdk
    yes | sdkmanager --licenses >/dev/null 2>&1 || true
    sdkmanager "platforms;android-36" "build-tools;36.0.0" "ndk;28.2.13676358" \
      "platform-tools" >/dev/null

    mkdir -p "$REPRO" && cd "$REPRO"
    # A clean copy of the commit, not the working tree: no .git, no build/, nothing
    # a laptop leaves behind that a fresh clone would not have.
    git -C /src archive "$COMMIT" | tar -x -C "$REPRO"

    git clone -q --depth 1 --branch "$FLUTTER_VERSION" \
      https://github.com/flutter/flutter.git /opt/flutter-pinned
    export PATH=/opt/flutter-pinned/bin:$PATH
    export PUB_CACHE="$REPRO/.pub-cache"
    git config --global --add safe.directory /opt/flutter-pinned
    flutter config --no-analytics >/dev/null
    flutter pub get --enforce-lockfile

    # Signed here rather than afterwards, because a signature applied to an APK that
    # has already been zipaligned by somebody else is exactly the kind of difference
    # the comparison trips over.
    cat > android/key.properties <<KEY
storeFile=/keys/textlog-release.jks
storePassword=$(cat /keys/textlog-release.password)
keyPassword=$(cat /keys/textlog-release.password)
keyAlias=textlog
KEY

    # One ABI at a time, exactly as the recipe does it — each of its two build
    # entries runs a single --target-platform. Building all three at once is both
    # further from what F-Droid runs and slower, and it drags in x86_64, which
    # nothing ships: it is the emulator slice, and the CMake configure step the
    # `jni` package runs for it fails under emulation for reasons that have nothing
    # to do with this app.
    flutter build apk --release --split-per-abi --target-platform=android-arm
    flutter build apk --release --split-per-abi --target-platform=android-arm64

    apk=build/app/outputs/flutter-apk
    cp "$apk/app-arm64-v8a-release.apk"   "/out/textlog-$VERSION-arm64-v8a.apk"
    cp "$apk/app-armeabi-v7a-release.apk" "/out/textlog-$VERSION-armeabi-v7a.apk"
    rm -f android/key.properties
  '

echo
sha256sum "$out"/*.apk
echo
echo "Attach these to the v$version release — the ones F-Droid rebuilds and compares."
