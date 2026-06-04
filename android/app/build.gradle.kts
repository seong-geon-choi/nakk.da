import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProps = Properties().also { props ->
    val f = rootProject.file("key.properties")
    if (f.exists()) props.load(f.inputStream())
}

android {
    namespace = "com.nakkda.nakkda"
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
        applicationId = "com.nakkda.nakkda"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            keyAlias     = keyProps["keyAlias"]     as String
            keyPassword  = keyProps["keyPassword"]  as String
            storeFile    = rootProject.file(keyProps["storeFile"] as String)
            storePassword = keyProps["storePassword"] as String
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }
}

dependencies {
    implementation("com.google.ar:core:1.44.0")
    implementation("androidx.documentfile:documentfile:1.0.1")
}

flutter {
    source = "../.."
}
