import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release signing — a real keystore when android/key.properties exists
// (owner-created; see android/key.properties.example + docs/RELEASE_SIGNING.md),
// falling back to the debug keys otherwise so `flutter run --release` works on
// machines without the secret. Production APKs MUST be built on a machine that
// has key.properties — a debug-signed build cannot be upgraded in place by a
// properly signed one. Mirrors pos_handheld's scaffold (43145fc).
val keystoreProperties = Properties()
val keystorePropertiesFile = rootProject.file("key.properties")
val hasReleaseKeystore = keystorePropertiesFile.exists()
if (hasReleaseKeystore) {
    // readText + BOM strip: a key.properties saved from Notepad carries a
    // UTF-8 BOM that would silently corrupt the first key (storeFile gets
    // an invisible U+FEFF prefix) and fail the build with a cryptic
    // null-cast error.
    val text = keystorePropertiesFile.readText(Charsets.UTF_8).removePrefix("\uFEFF")
    keystoreProperties.load(text.reader())
}

android {
    namespace = "com.example.pos_machine"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.example.pos_machine"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKeystore) {
            create("release") {
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
                // Path relative to the android/ folder (or absolute) — keep
                // the .jks itself OUT of the repo.
                storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKeystore) {
                signingConfigs.getByName("release")
            } else {
                // No keystore on this machine: debug keys, so `flutter run
                // --release` still works. NOT for production distribution.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation(files("libs/libsunmifingeprint_v1.0.0.aar"))
}
