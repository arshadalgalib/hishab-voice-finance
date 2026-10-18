import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// ── Release signing ───────────────────────────────────────────────────────────
// Put storeFile / storePassword / keyAlias / keyPassword in `android/key.properties`
// (git-ignored — see `key.properties.example`). Without that file the release
// build falls back to the debug key so `flutter build` still works on a fresh
// clone, in CI, and for local evaluation; the fallback is never publishable.
val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties =
    Properties().apply {
        if (keystorePropertiesFile.exists()) {
            FileInputStream(keystorePropertiesFile).use { load(it) }
        }
    }
val hasReleaseKeystore = keystorePropertiesFile.exists()

// `flutter build apk --split-per-abi` makes AGP emit one APK per ABI, and AGP
// rejects `ndk.abiFilters` whenever ABI splits are enabled ("Conflicting
// configuration"). So pin ABIs only for the non-split build (the default
// `flutter build apk --release`), where dropping the emulator-only x86_64
// removes ~25 MB of native libraries from the download.
val splitPerAbi = (project.findProperty("split-per-abi") as? String)?.toBoolean() ?: false

android {
    namespace = "bd.pfm.personal_finance_manager"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // Required by flutter_local_notifications, which uses java.time on the
        // scheduled-notification paths on every supported API level.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "bd.pfm.personal_finance_manager"

        // 23 (Android 6) is the floor required by flutter_secure_storage 11
        // (Keystore-backed EncryptedSharedPreferences) and local_auth 3.
        minSdk = maxOf(23, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion

        versionCode = flutter.versionCode
        versionName = flutter.versionName

        // Ship only the ABIs real phones use. x86_64 exists purely for the
        // emulator; bundling it in a release build adds ~25 MB of native
        // libraries (`libflutter.so` + `libapp.so` + `libsqlite3.so`) that no
        // real device ever downloads. It is re-added for the `debug` build type
        // below so emulator development keeps working. Skipped entirely when
        // `--split-per-abi` already produces a per-architecture artifact.
        if (!splitPerAbi) {
            ndk {
                abiFilters.clear()
                abiFilters += listOf("arm64-v8a", "armeabi-v7a")
            }
        }
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                storeFile = file(keystoreProperties.getProperty("storeFile"))
                storePassword = keystoreProperties.getProperty("storePassword")
                keyAlias = keystoreProperties.getProperty("keyAlias")
                keyPassword = keystoreProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        debug {
            // The standard emulator is x86_64, so debug builds keep it.
            if (!splitPerAbi) {
                ndk {
                    abiFilters.clear()
                    abiFilters += listOf("arm64-v8a", "armeabi-v7a", "x86_64")
                }
            }
        }
        release {
            signingConfig =
                if (hasReleaseKeystore) {
                    signingConfigs.getByName("release")
                } else {
                    logger.warn(
                        "android/key.properties not found — the release build is signed with the " +
                            "DEBUG key. Create android/key.properties (see key.properties.example) " +
                            "before publishing.",
                    )
                    signingConfigs.getByName("debug")
                }

            // R8 strips unused Java/Kotlin code and resource shrinking drops
            // unreferenced resources. Flutter's Gradle plugin wires up
            // `proguard-android-optimize.txt`, its own `flutter_proguard_rules.pro`
            // and `android/app/proguard-rules.pro` when this is enabled, so the
            // plugin keeps in `proguard-rules.pro` are applied too.
            isMinifyEnabled = true
            isShrinkResources = true
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

flutter {
    source = "../.."
}
