import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    id("org.jetbrains.kotlin.plugin.compose")
}

// 폰 앱과 동일한 서명키를 사용해야 Wear Data Layer가 연결된다(같은 패키지명 + 같은 인증서).
val keyProps = Properties().also { props ->
    val f = rootProject.file("key.properties")
    if (f.exists()) props.load(f.inputStream())
}

android {
    namespace = "com.sgchoisg.nakkda"
    compileSdk = 35

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // 폰 앱과 반드시 동일(Data Layer 전제 조건).
        applicationId = "com.sgchoisg.nakkda"
        // Galaxy Watch 4 하드웨어(Wear OS 3=API30)부터 설치되도록. 테스트는 Wear OS 4 에뮬레이터.
        minSdk = 30
        // Play 타깃 API 요구치(API 35). compileSdk와 일치.
        targetSdk = 35
        // Wear 번들 versionCode는 폰(2077)보다 크고 고유해야 함(Play 규칙: 폼팩터 무관
        // 패키지 내 versionCode 고유 + 워치 ≥ 폰). 2076→2078: 폰 2077에 맞춰 상향(스플래시 수정).
        versionCode = 2078
        versionName = "3.14.3"
    }

    buildFeatures {
        compose = true
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
            // 폰 앱과 동일하게 디버그도 릴리즈 키로 서명 — 같은 인증서라야
            // 디버그/릴리즈 아무 조합이나 Wear Data Layer가 연동된다(개발 편의).
            signingConfig = signingConfigs.getByName("release")
        }
        release {
            signingConfig = signingConfigs.getByName("release")
            isMinifyEnabled = false
        }
    }
}

dependencies {
    implementation(platform("androidx.compose:compose-bom:2024.12.01"))
    implementation("androidx.wear.compose:compose-material:1.4.1")
    implementation("androidx.wear.compose:compose-foundation:1.4.1")
    // 화면 꺼짐(앰비언트)에도 앱이 활성 상태로 유지되도록(워치페이스로 안 돌아감).
    implementation("androidx.wear:wear:1.3.0")
    // Ongoing Activity: show an in-progress icon on the watch face to return to the app.
    implementation("androidx.wear:wear-ongoing:1.0.0")
    implementation("androidx.compose.foundation:foundation")
    implementation("androidx.compose.animation:animation")
    implementation("androidx.activity:activity-compose:1.9.3")
    implementation("androidx.core:core-ktx:1.15.0")
    // 시작 스플래시(검정 배경 + 48dp 아이콘). 1.0.1+ 라야 Wear OS 기본 치수 지원.
    implementation("androidx.core:core-splashscreen:1.0.1")
    implementation("com.google.android.gms:play-services-wearable:18.2.0")
    // 전이 의존성으로 딸려오는 오래된 fragment(1.1.0)를 최신으로 강제(Play SDK 경고 해소).
    implementation("androidx.fragment:fragment:1.8.6")
}
