# kotlinx.serialization keeps the generated serializers for @Serializable types.
-keepattributes *Annotation*, InnerClasses
-dontnote kotlinx.serialization.**

-keepclassmembers class dev.plocic.nightride.** {
    *** Companion;
}
-keepclasseswithmembers class dev.plocic.nightride.** {
    kotlinx.serialization.KSerializer serializer(...);
}

# OkHttp ships optional platform integrations it references reflectively.
-dontwarn okhttp3.internal.platform.**
-dontwarn org.conscrypt.**
-dontwarn org.bouncycastle.**
-dontwarn org.openjsse.**
