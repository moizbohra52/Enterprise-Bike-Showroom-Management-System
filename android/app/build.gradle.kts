plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.enterprise.bikeshowroom"

    // `flutter.compileSdkVersion` is whatever the installed Flutter SDK
    // defaults to, and older SDKs still default to 34. The AndroidX / Firebase /
    // plugin artifacts that `pub` resolves today publish a `minCompileSdk` in
    // their AAR metadata, so a lower value fails the build with
    // `:app:checkDebugAarMetadata` ("The minCompileSdk (35) specified in a
    // dependency's AAR metadata is greater than this module's compileSdkVersion").
    // Keep the SDK default when it is already newer.
    compileSdk = maxOf(flutter.compileSdkVersion, 35)
    ndkVersion = flutter.ndkVersion

    // AGP 8 needs JDK 17 to run and current AndroidX artifacts ship Java 17
    // bytecode; Java and Kotlin must agree or Gradle fails with
    // "Inconsistent JVM-target compatibility detected".
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.enterprise.bikeshowroom"
        // 21 is the Flutter floor, but flutter_secure_storage / permission_handler /
        // printing / image_picker and AndroidX itself keep raising theirs; 23
        // (Android 6.0) keeps the manifest merger quiet for this app's audience.
        minSdk = maxOf(flutter.minSdkVersion, 23)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}
