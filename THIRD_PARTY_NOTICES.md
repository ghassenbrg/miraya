# Third-party notices

Miraya's source code is MIT licensed; see [LICENSE](LICENSE).

The Android application uses Kotlin standard-library code, copyright JetBrains s.r.o. and Kotlin Programming Language contributors, under the [Apache License 2.0](licenses/Apache-2.0.txt). The Android APK includes corresponding license/notice assets. Kotlin compiler, Gradle, Android Gradle Plugin and Android test libraries are build/development dependencies governed by their respective upstream licenses.

The macOS application uses Apple system frameworks provided by macOS. The Android application uses Android platform media, security and network APIs provided by the device OS. These platform implementations are not copied into the repository. H.264 encoding/decoding is performed by the OS/platform media stack.

No third-party media relay, bundled FFmpeg binary, WebRTC library, or external audio driver is shipped with Miraya. Optional developer validation may invoke a locally installed FFmpeg executable, which remains separately installed software under its own build's license.
