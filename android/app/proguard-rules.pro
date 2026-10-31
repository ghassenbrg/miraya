# The pinned WebRTC AAR ships no consumer rules. JNI_OnLoad looks up Java
# classes/methods by their upstream names, including code referenced only from
# its native library. Keep that library boundary intact in optimized releases.
-keep class org.webrtc.** { *; }
# Keep the native entry points in JNI Zero without retaining its unused
# setJniClassLoader helper (the AAR does not ship its generated JniZeroJni stub).
-keepclasseswithmembers,includedescriptorclasses class org.jni_zero.** {
    @org.jni_zero.CalledByNative <methods>;
}
