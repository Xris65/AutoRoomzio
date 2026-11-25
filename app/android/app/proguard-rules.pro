# Flutter & Android embedding
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.embedding.** { *; }
-keep class com.autoroomzio.app.** { *; }
-dontwarn io.flutter.embedding.**

# Gson / Serialization (R8 Full Mode compatibility for flutter_local_notifications & plugins)
-keepattributes Signature, *Annotation*, EnclosingMethod, InnerClasses
-keep class com.google.gson.** { *; }
-keep class * extends com.google.gson.reflect.TypeToken
-keepclassmembers class * extends com.google.gson.reflect.TypeToken { <init>(); }
-keepclassmembers class * {
    @com.google.gson.annotations.SerializedName <fields>;
}

# flutter_local_notifications
-keep class com.dexterous.** { *; }

# workmanager (AndroidX WorkManager consumer rules are bundled upstream)
-keep class dev.fluttercommunity.workmanager.** { *; }
-keepclassmembers class * extends androidx.work.Worker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}
-keepclassmembers class * extends androidx.work.ListenableWorker {
    public <init>(android.content.Context, androidx.work.WorkerParameters);
}

# flutter_secure_storage
-keep class com.it_nomads.fluttersecurestorage.** { *; }
-dontwarn com.google.crypto.tink.**
-dontwarn javax.annotation.**

# webview_flutter & open_filex
-keep class io.flutter.plugins.webviewflutter.** { *; }
-keep class com.crazecoder.openfile.** { *; }
