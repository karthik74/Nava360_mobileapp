plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
    id("com.google.gms.google-services")
}

import java.io.FileInputStream
import java.util.Properties

val keystorePropertiesFile = rootProject.file("key.properties")
val keystoreProperties = Properties().apply {
    if (keystorePropertiesFile.exists()) {
        load(FileInputStream(keystorePropertiesFile))
    }
}

android {
    namespace = "com.hrms.nava_360"
    compileSdk = flutter.compileSdkVersion
    // Pin to the NDK actually installed on this machine — flutter.ndkVersion
    // references a version that isn't present, which makes release BUNDLE
    // builds fail at "strip debug symbols" (APK builds don't hit it).
    ndkVersion = "28.2.13676358"

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // Required by flutter_local_notifications (uses java.time on minSdk < 26).
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // Must match the Android app registered in Firebase
        // (see android/app/google-services.json).
        applicationId = "com.hrms.nava_360"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    // ── Company flavors (white-label) ────────────────────────────────────────
    // One Play Store listing per company: each flavor has its own application
    // id, launcher name and icon (src/<flavor>/res/mipmap-*), and Env.dart maps
    // the flavor to that company's backend URL. EVERY applicationId below must
    // be registered as an Android app in the same Firebase project and be
    // present in google-services.json, or that flavor's build fails.
    // Build:  flutter build appbundle --release --flavor laxmi   (etc.)
    // Run:    flutter run --flavor livelihoods
    flavorDimensions += "company"
    productFlavors {
        create("livelihoods") {
            dimension = "company"
            // The original id — keeps the existing Play listing + installs.
            applicationId = "com.hrms.nava_360"
            resValue("string", "app_name", "Nava360")
        }
        create("souhardha") {
            dimension = "company"
            applicationId = "com.hrms.nava_360.souhardha"
            resValue("string", "app_name", "Navachetana Souhardha")
        }
        create("laxmi") {
            dimension = "company"
            applicationId = "com.hrms.nava_360.laxmi"
            resValue("string", "app_name", "Laxmi Multistate")
        }
    }

    signingConfigs {
        create("release") {
            if (keystorePropertiesFile.exists()) {
                storeFile = file(keystoreProperties["storeFile"] as String)
                storePassword = keystoreProperties["storePassword"] as String
                keyAlias = keystoreProperties["keyAlias"] as String
                keyPassword = keystoreProperties["keyPassword"] as String
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (keystorePropertiesFile.exists()) {
                signingConfigs.getByName("release")
            } else {
                // Fallback so local release builds still work until you create a keystore.
                signingConfigs.getByName("debug")
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
