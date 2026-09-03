# R8/ProGuard keep 규칙 — 릴리스 코드 축소 시 JNI·리플렉션으로 참조되는
# 클래스가 제거돼 릴리스 전용 크래시가 나지 않도록 보존한다.
# (대부분의 Flutter 플러그인은 자체 consumer 규칙을 AAR에 포함하지만,
#  네이티브 의존성은 안전차원에서 명시적으로 keep 한다.)

# ── Flutter 엔진/임베딩 ───────────────────────────────
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.embedding.** { *; }
-dontwarn io.flutter.**

# ── ARCore (com.google.ar:core) — 네이티브 ────────────
-keep class com.google.ar.** { *; }
-dontwarn com.google.ar.**

# ── TensorFlow Lite (tflite_flutter) — JNI ────────────
-keep class org.tensorflow.** { *; }
-keep class org.tensorflow.lite.** { *; }
-dontwarn org.tensorflow.**

# ── Google Play Core (in_app_update) ──────────────────
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**

# ── 앱 네이티브 진입점(Activity/Service는 매니페스트 참조라 자동 keep이지만
#    메서드 채널 핸들러 등을 포함해 안전차원에서 앱 패키지 전체 보존) ──
-keep class com.sgchoisg.nakkda.** { *; }

# ── 공통 방어 규칙(리플렉션·JNI·enum 관련 릴리스 크래시 예방) ──
-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod
-keepclassmembers class * {
    native <methods>;
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}
