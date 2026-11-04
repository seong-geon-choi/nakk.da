import java.util.Properties
import java.util.Date
import java.text.SimpleDateFormat

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

val keyProps = Properties().also { props ->
    val f = rootProject.file("key.properties")
    if (f.exists()) props.load(f.inputStream())
}

val buildTime = SimpleDateFormat("yyyy-MM-dd HH:mm").format(Date())

android {
    namespace = "com.sgchoisg.nakkda"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    buildFeatures {
        buildConfig = true
    }

    defaultConfig {
        applicationId = "com.sgchoisg.nakkda"
        minSdk = 26
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        buildConfigField("String", "BUILD_TIME", "\"$buildTime\"")
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
        debug {
            // 디버그도 릴리즈 키로 서명 — 디버그/릴리즈가 같은 인증서라
            // 서로 덮어 설치되고(데이터·SAF 권한 보존) 워치 Data Layer도 연동된다(개발 편의).
            signingConfig = signingConfigs.getByName("release")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            // R8 코드 축소·난독화 활성(Play 앱 최적화 '난독화' 기준 충족).
            // keep 규칙은 proguard-rules.pro 참조. mapping.txt는 AAB에 포함되어
            // Play Console이 크래시 역난독화에 자동 사용한다.
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )
        }
    }
}

dependencies {
    implementation("com.google.ar:core:1.44.0")
    implementation("androidx.documentfile:documentfile:1.0.1")
    implementation("com.google.android.gms:play-services-location:21.3.0")
    // Wear OS 워치 연동(Data Layer: MessageClient/WearableListenerService).
    implementation("com.google.android.gms:play-services-wearable:18.2.0")
}

flutter {
    source = "../.."
}
