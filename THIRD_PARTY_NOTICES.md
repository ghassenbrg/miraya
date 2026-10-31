# Third-party notices

Miraya's source code is MIT licensed; see [LICENSE](LICENSE).

Android direct playback uses [AndroidX Media3 1.11.1](https://github.com/androidx/media/tree/1.11.1): ExoPlayer, HLS/DASH and native player controls, with their AndroidX dependencies, under the [Apache License 2.0](licenses/Apache-2.0.txt). The APK includes `assets/licenses/Media3-NOTICE.txt` and the license. No FFmpeg extension is bundled.

The Android application uses Kotlin standard-library code, copyright JetBrains s.r.o. and Kotlin Programming Language contributors, under the [Apache License 2.0](licenses/Apache-2.0.txt). The Android APK includes corresponding license/notice assets. Kotlin compiler, Gradle, Android Gradle Plugin and Android test libraries are build/development dependencies governed by their respective upstream licenses.

The macOS application uses Apple system frameworks provided by macOS. The Android application uses Android platform media, security and network APIs provided by the device OS. These platform implementations are not copied into the repository. H.264 encoding/decoding is performed by the OS/platform media stack.

Both applications bundle native WebRTC M150. The Mac uses [stasel/WebRTC 150.0.0](https://github.com/stasel/WebRTC/tree/150.0.0), pinned by SwiftPM including its binary checksum; Android uses [io.github.webrtc-sdk:android:150.7871.04](https://github.com/webrtc-sdk/android). WebRTC is BSD licensed; the Android distribution wrapper is MIT licensed and its fork includes Apache-licensed modifications. WebRTC includes third-party code such as Opus, BoringSSL, libSRTP, libyuv, Abseil and software codecs. License texts, upstream source locations and fork notices are included in [WebRTC-NOTICES.txt](licenses/WebRTC-NOTICES.txt), and copied into both packaged apps. The collection includes upstream M150 dependency notices conservatively across both platforms.

`macos/Sources/MirayaRTCBridge/RTCAudioDevice.h` comes from WebRTC branch-heads/7871 and retains its BSD copyright notice. The bridge implementation is Miraya code. The custom audio device accepts only captured system audio, with no microphone driver.

No third-party media relay, bundled FFmpeg executable, or external audio driver is shipped. Optional developer validation may invoke a separately installed FFmpeg executable under its own build's license. Apple/Android hardware H.264 support and protected-content policies remain platform responsibilities.
