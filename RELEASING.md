# Releasing

Manual for now: build the APK, create a GitHub release, attach it.

## 1. Set the version

`pubspec.yaml`, `version: <name>+<code>`. The build number must go **up** every release or
Android refuses to install over the previous one.

```yaml
version: 0.0.1+1
```

## 2. Build

**Build both.** The split builds are what people actually download — a universal APK
carries every architecture, so it is roughly three times the size of the one your phone can
use, and attaching only that one wastes most of every download.

```sh
flutter build apk --release                  # universal, ~55MB
flutter build apk --release --split-per-abi  # per-device, ~18-20MB each
```

Output: `build/app/outputs/flutter-apk/`

The split builds get an ABI-prefixed `versionCode` — `2019` for arm64, `1019` for v7a from a
pubspec `+19`. That is Flutter's doing and it is correct: it keeps a device from installing
the wrong slice over the right one.

Verify before shipping — a release APK without `INTERNET` reaches nothing and every screen
errors, and the Flutter template only grants it in the debug manifest:

```sh
aapt2 dump badging build/app/outputs/flutter-apk/app-release.apk \
  | grep -E "^package|uses-permission|application-label:"
```

Expect `versionName` to match pubspec and `android.permission.INTERNET` to be listed.

## 3. Tag and release

```sh
git tag v0.0.1
git push origin v0.0.1
```

Then on GitHub: **Releases → Draft a new release → pick tag `v0.0.1`**, and tick **"This is
a pre-release"**.

**Four assets, renamed so a downloads folder still makes sense a version later:**

| Build | Attach as |
|---|---|
| `app-arm64-v8a-release.apk` | `textlog-0.0.1-arm64-v8a.apk` |
| `app-armeabi-v7a-release.apk` | `textlog-0.0.1-armeabi-v7a.apk` |
| `app-release.apk` | `textlog-0.0.1.apk` |
| the disk image below | `textlog-0.0.1-macos.dmg` |

`app-x86_64-release.apk` is emulator-only — do not attach it. Say in the notes which file to
pick, or everyone takes the universal one because it has the shortest name.

```sh
gh release create v0.0.1 textlog-0.0.1*.apk textlog-0.0.1-macos.dmg \
  --title "v0.0.1 — …" --notes-file notes.md --prerelease
```

## Installing (for testers)

Android blocks APKs from outside the Play Store by default. On first open the phone will
offer to allow installs from the browser or files app — that has to be granted once.

## Signing

Release builds are signed with a real key from `android/key.properties`, which points at a
keystore kept **outside** the repo. Both are gitignored; the keystore has never been
committed and must not be.

```
~/keystores/textlog-release.jks        the key
~/keystores/textlog-release.password   its password
android/key.properties                 where Gradle looks (gitignored)
```

**Back both up somewhere you will still have in a year.** If the keystore is lost, no future
build can ever update an existing install — every user would have to uninstall and lose
their settings. There is no recovery: Android identifies an app by `applicationId` *and*
signature.

A clone without `key.properties` still builds; it falls back to debug signing.

Verify what you are about to ship:

```sh
apksigner verify --print-certs build/app/outputs/flutter-apk/app-release.apk
```

Expect `CN=textlog flutter client`. If it says `CN=Android Debug`, `key.properties` was not
picked up.

## macOS

```sh
flutter build macos --release
```

`macos/Runner/Release.entitlements` must keep `com.apple.security.network.client`. The
Flutter template grants it only in the debug profile, so without it the release build is
sandboxed with no outbound network and every screen errors — the same trap as the missing
INTERNET permission on Android. Verify it survived into the binary:

```sh
codesign -d --entitlements - --xml build/macos/Build/Products/Release/textlog.app \
  | plutil -convert xml1 -o - - | grep -A1 network.client
```

Wrap it as a disk image:

```sh
rm -rf /tmp/dmgroot && mkdir -p /tmp/dmgroot
cp -R build/macos/Build/Products/Release/textlog.app /tmp/dmgroot/
ln -s /Applications /tmp/dmgroot/Applications
hdiutil create -volname "textlog <version>" -srcfolder /tmp/dmgroot -ov -format UDZO \
  textlog-<version>-macos.dmg
```

The build is **ad-hoc signed** (`TeamIdentifier=not set`). It runs, but Gatekeeper blocks it
on a machine that downloaded it until the user allows it explicitly. Notarising would need a
paid Apple developer account.

## iOS

Not yet built. It needs the iOS platform SDK installed in Xcode:

```sh
xcodebuild -downloadPlatform iOS    # several GB, one time
flutter build ios --release --no-codesign
```

That produces an **unsigned** `.app`. It cannot be installed by tapping it — a recipient
needs AltStore, Sideloadly or similar plus their own Apple ID, and a free Apple ID re-signs
only for 7 days at a time.

The App Store is not an option regardless: this project is AGPL, which has historically been
incompatible with Apple's terms. See the licence note in the README.
