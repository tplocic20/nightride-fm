# kotlinx.serialization keeps the generated serializers for @Serializable types.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-keepclassmembers class fm.nightride.android.** {
    *** Companion;
}
-keepclasseswithmembers class fm.nightride.android.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# OkHttp ships optional platform integrations it references reflectively.
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
