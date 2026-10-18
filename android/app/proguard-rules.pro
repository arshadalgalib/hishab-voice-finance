# R8/ProGuard rules for the release build.
#
# Flutter's Gradle plugin already contributes `proguard-android-optimize.txt`
# and its own `flutter_proguard_rules.pro`; this file only adds the keeps that
# the app's own plugins need. It is picked up automatically because it sits next
# to `build.gradle.kts` under `android/app/`.

# ── flutter_local_notifications ──────────────────────────────────────────────
# The plugin persists scheduled bill/budget notifications as JSON with Gson,
# which reads and writes the model fields through reflection. R8 cannot see
# those accesses, so without these rules the fields are renamed/removed and
# every scheduled reminder silently stops surviving a reboot.
-keep class com.dexterous.flutterlocalnotifications.** { *; }
-keep class com.google.gson.** { *; }
-dontwarn com.google.gson.**

# Gson needs the generic signatures and annotations it reflects over
# (`@SerializedName`, `TypeToken<…>`, the polymorphic `RuntimeTypeAdapterFactory`).
-keepattributes Signature
-keepattributes *Annotation*
-keepattributes InnerClasses
-keepattributes EnclosingMethod

# ── flutter_secure_storage / Tink ────────────────────────────────────────────
# Tink loads its key primitives reflectively; keep the classes it looks up.
-keep class com.google.crypto.tink.** { *; }
-dontwarn com.google.crypto.tink.**

# ── local_auth (androidx.biometric) ──────────────────────────────────────────
-keep class androidx.biometric.** { *; }
-dontwarn androidx.biometric.**
