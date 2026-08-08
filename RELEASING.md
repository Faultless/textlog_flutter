# Releasing

Manual for now: build the APK, create a GitHub release, attach it.

## 1. Set the version

`pubspec.yaml`, `version: <name>+<code>`. The build number must go **up** every release or
Android refuses to install over the previous one.

```yaml
version: 0.0.1+1
```

## 2. Build

```sh
flutter build apk --release                  # universal, ~48MB
flutter build apk --release --split-per-abi  # per-device, ~15-18MB each
```

Output: `build/app/outputs/flutter-apk/`

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

Then on GitHub: **Releases → Draft a new release → pick tag `v0.0.1`**, attach
`app-release.apk`, and tick **"This is a pre-release"**.

Rename the file to `textlog-0.0.1.apk` when attaching, so people can tell versions apart in
their downloads folder.

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
