plugins { id("com.android.application"); id("org.jetbrains.kotlin.android") }
val mirayaVersion = rootProject.file("../VERSION").readText().trim()
require(Regex("[0-9]+\\.[0-9]+\\.[0-9]+").matches(mirayaVersion)) { "VERSION must be X.Y.Z" }
val mirayaBuild = System.getenv("MIRAYA_BUILD_NUMBER")?.toIntOrNull() ?: 6
require(mirayaBuild in 1..2100000000) { "MIRAYA_BUILD_NUMBER must be a positive Android version code" }
val signingVariables = listOf("MIRAYA_KEYSTORE", "MIRAYA_STORE_PASSWORD", "MIRAYA_KEY_ALIAS", "MIRAYA_KEY_PASSWORD")
val suppliedSigningVariables = signingVariables.filter { !System.getenv(it).isNullOrBlank() }
if (suppliedSigningVariables.isNotEmpty() && suppliedSigningVariables.size != signingVariables.size) {
    throw GradleException("Release signing requires all of: " + signingVariables.joinToString(", ") + ". Missing: " + (signingVariables - suppliedSigningVariables.toSet()).joinToString(", "))
}
android {
    namespace = "dev.miraya.tv"
    compileSdk = 36
    buildToolsVersion = "36.0.0"
    defaultConfig { applicationId = "dev.miraya.tv"; minSdk = 26; targetSdk = 35; versionCode = mirayaBuild; versionName = mirayaVersion; testInstrumentationRunner = "androidx.test.runner.AndroidJUnitRunner" }
    sourceSets.getByName("androidTest").assets.srcDir(rootProject.file("../build/capture-fixture"))
    signingConfigs {
        create("release") {
            val path = System.getenv("MIRAYA_KEYSTORE")
            if (path != null) {
                require(file(path).isFile) { "MIRAYA_KEYSTORE does not point to a readable keystore file" }
                storeFile = file(path); storePassword = System.getenv("MIRAYA_STORE_PASSWORD")
                keyAlias = System.getenv("MIRAYA_KEY_ALIAS"); keyPassword = System.getenv("MIRAYA_KEY_PASSWORD")
            }
        }
    }
    buildTypes {
        release { isMinifyEnabled = true; proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro"); if (System.getenv("MIRAYA_KEYSTORE") != null) signingConfig = signingConfigs.getByName("release") }
    }
    compileOptions { sourceCompatibility = JavaVersion.VERSION_17; targetCompatibility = JavaVersion.VERSION_17 }
    kotlinOptions { jvmTarget = "17" }
    testOptions { unitTests.isReturnDefaultValues = true }
}
dependencies {
    val media3 = "1.11.1"
    implementation("androidx.media3:media3-exoplayer:$media3")
    implementation("androidx.media3:media3-exoplayer-hls:$media3")
    implementation("androidx.media3:media3-exoplayer-dash:$media3")
    implementation("androidx.media3:media3-ui:$media3")
    implementation("io.github.webrtc-sdk:android:150.7871.04")
    testImplementation("junit:junit:4.13.2")
    androidTestImplementation("androidx.test:runner:1.6.2")
    androidTestImplementation("androidx.test:core:1.6.1")
    androidTestImplementation("androidx.test.ext:junit:1.2.1")
    androidTestImplementation("androidx.test.uiautomator:uiautomator:2.3.0")
}
