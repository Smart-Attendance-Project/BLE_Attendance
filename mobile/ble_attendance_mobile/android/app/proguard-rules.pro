# TFLite Flutter — keep GPU delegate classes that R8 can't resolve
-dontwarn org.tensorflow.lite.gpu.**
-keep class org.tensorflow.lite.** { *; }
-keep class org.tensorflow.lite.gpu.** { *; }

# Google ML Kit
-keep class com.google.mlkit.** { *; }
-dontwarn com.google.mlkit.**
