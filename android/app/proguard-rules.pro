# Flutter-specific ProGuard rules
# Keep Flutter engine and platform classes
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }
-keep class io.flutter.plugin.** { *; }

# Keep Firebase classes
-keep class com.google.firebase.** { *; }
-keep class com.google.android.gms.** { *; }

# Keep classes annotated with @Keep
-keep @androidx.annotation.Keep class * { *; }

# Keep Hive model classes
-keep class ** extends com.google.flatbuffers.Table { *; }

# Prevent stripping of Dart entrypoint
-keep class **.R
-keep class **.R$* { *; }

# General Android rules
-keepattributes *Annotation*
-keepattributes SourceFile,LineNumberTable
-dontwarn **
