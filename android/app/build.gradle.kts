plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.example.cctv_app"
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
        applicationId = "com.example.cctv_app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // One flavor per backend environment. The flavor name is exposed to Dart
    // as `appFlavor` and selects the matching entry in
    // lib/core/config/environment_registry.dart (APP_ENV overrides it).
    // Cleartext HTTP is allowed only for `local` (backend on the developer's
    // machine) and `development` (its server is plain http://); qa and
    // production are HTTPS-only.
    flavorDimensions += "environment"
    productFlavors {
        create("local") {
            dimension = "environment"
            applicationIdSuffix = ".local"
            versionNameSuffix = "-local"
            resValue("string", "app_name", "Enrolly Local")
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        create("development") {
            dimension = "environment"
            applicationIdSuffix = ".dev"
            versionNameSuffix = "-dev"
            resValue("string", "app_name", "Enrolly Dev")
            // The development server (http://27.147.174.107:8085) is plain HTTP.
            manifestPlaceholders["usesCleartextTraffic"] = "true"
        }
        create("qa") {
            dimension = "environment"
            applicationIdSuffix = ".qa"
            versionNameSuffix = "-qa"
            resValue("string", "app_name", "Enrolly QA")
            manifestPlaceholders["usesCleartextTraffic"] = "false"
        }
        create("production") {
            dimension = "environment"
            resValue("string", "app_name", "Enrolly")
            manifestPlaceholders["usesCleartextTraffic"] = "false"
        }
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
