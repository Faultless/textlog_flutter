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
flutter build apk --release
```

Output: `build/app/outputs/flutter-apk/app-release.apk`

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

## Known limitations of these builds

- **Debug-signed.** `android/app/build.gradle.kts` still uses `signingConfigs.debug` for
  release builds. They install and run, but Android shows an unverified-app warning, and a
  future differently-signed build will **not** install over one of these — testers will
  have to uninstall first. Worth fixing before asking anyone to keep the app installed.
- **Universal APK, ~49MB.** One file that works on every device. `--split-per-abi` cuts it
  to roughly a third each, at the cost of testers having to pick the right one.
