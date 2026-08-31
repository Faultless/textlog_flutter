import com.android.build.gradle.internal.api.ApkVariantOutputImpl
import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing details live in android/key.properties, which is gitignored — the
// keystore itself is kept outside the repo entirely. Without it (a fresh clone, CI),
// the release build falls back to debug signing so it still builds.
val keyProperties = Properties().apply {
    val file = rootProject.file("key.properties")
    if (file.exists()) file.inputStream().use { load(it) }
}

android {
    namespace = "dev.serge.textlog"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    // The Android Gradle Plugin otherwise writes a signed blob of dependency
    // metadata into the APK's signing block, for the Play Store to read. F-Droid's
    // scanner rejects an APK carrying an extra signing block it cannot account for,
    // and nothing here wants Google reading a dependency list either way.
    dependenciesInfo {
        includeInApk = false
        includeInBundle = false
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications uses java.time, which needs desugaring to run
        // on the older API levels this app still supports.
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.serge.textlog"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyProperties.containsKey("storeFile")) {
            create("release") {
                storeFile = file(keyProperties["storeFile"] as String)
                storePassword = keyProperties["storePassword"] as String
                keyAlias = keyProperties["keyAlias"] as String
                keyPassword = keyProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            // One line on purpose. F-Droid strips signing configuration out of the
            // build file before it builds, with a line-based regex that matches
            // `signingConfig = <no-spaces>` — which used to delete the first line of
            // this expression and leave the `?:` continuation behind as a syntax
            // error, so their build of this app could not compile at all. With the
            // whole expression on one line the regex does not match, the line
            // survives, the release config it looks for is simply not there, and it
            // falls back to the debug key exactly as an unsigned build should.
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
        }
    }
}

// Per-ABI version codes, F-Droid's scheme rather than Flutter's.
//
// Flutter's own `--split-per-abi` offsets the code by 1000 for armeabi-v7a and 2000
// for arm64-v8a, which leaves gaps in the hundreds and sorts oddly against the
// universal build. F-Droid asks for `code * 10 + n`, which keeps every published code
// ordered and adjacent — 251 and 252 for pubspec's `+25`. Requested in review on
// fdroiddata!47312, and it is what their other Flutter apps do.
val abiCodes = mapOf("armeabi-v7a" to 1, "arm64-v8a" to 2, "x86_64" to 3)
android.applicationVariants.configureEach {
    val variant = this
    variant.outputs.forEach { output ->
        val abiVersionCode = abiCodes[output.filters.find { it.filterType == "ABI" }?.identifier]
        if (abiVersionCode != null) {
            (output as ApkVariantOutputImpl).versionCodeOverride = variant.versionCode * 10 + abiVersionCode
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}
