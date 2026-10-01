# Flutter & Android entry points
-keep class com.nightcode.luci.MainActivity { *; }
-keep class io.flutter.plugins.GeneratedPluginRegistrant { *; }

# Flutter plugin lifecycle & instantiation (targeted rather than broad { *; })
# Allows R8 to shrink, inline, and obfuscate internal plugin code while preserving
# reflection/instantiation entry points required by Flutter's GeneratedPluginRegistrant.
-keep class * implements io.flutter.embedding.engine.plugins.FlutterPlugin {
    public <init>();
}
-keep class * implements io.flutter.embedding.engine.plugins.activity.ActivityAware {
    public <init>();
}

# Preserve native JNI methods & annotations across all classes
-keepclasseswithmembernames class * {
    native <methods>;
}
-keep @androidx.annotation.Keep class * { *; }
-keepclassmembers class * {
    @androidx.annotation.Keep *;
}

# Preserve attributes necessary for async execution, stack de-obfuscation, and reflection
-keepattributes *Annotation*,Signature,InnerClasses,EnclosingMethod,Exceptions
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# R8 aggressive optimization and class repackaging
# Moving classes into package 'a' maximizes cross-package class merging and minification.
# allowaccessmodification allows R8 to widen visibility to public to enable aggressive method inlining.
-repackageclasses 'a'
-allowaccessmodification

# Suppress known non-fatal warnings from Flutter & AndroidX modular dependencies
-dontwarn io.flutter.embedding.**
-dontwarn io.flutter.plugins.**
-dontwarn androidx.window.**
-dontwarn androidx.core.**
-dontwarn androidx.security.**

# Strip verbose, debug, and info logs in production release bytecode
-assumenosideeffects class android.util.Log {
    public static *** d(...);
    public static *** v(...);
    public static *** i(...);
}