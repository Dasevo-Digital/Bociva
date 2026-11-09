import com.android.Version
import org.jetbrains.kotlin.gradle.dsl.JvmTarget
import org.jetbrains.kotlin.gradle.dsl.KotlinAndroidProjectExtension

plugins {
    id("com.android.library")
}

group = "dev.steenbakker.mobile_scanner"
version = "1.0-SNAPSHOT"

// AGP 9+ compiles Kotlin itself when built-in Kotlin is enabled (the default),
// but apps migrated by the Flutter tool disable it via android.builtInKotlin=false.
// Apply KGP whenever built-in Kotlin is not active, so the Kotlin extension
// configured below exists in both configurations.
val agpMajor = Version.ANDROID_GRADLE_PLUGIN_VERSION.substringBefore('.').toInt()
val builtInKotlin = agpMajor >= 9 &&
    (findProperty("android.builtInKotlin")?.toString() ?: "true").toBoolean()
if (!builtInKotlin) {
    apply(plugin = "kotlin-android")
}

android {
    namespace = "dev.steenbakker.mobile_scanner"

    compileSdk = 36

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        minSdk = 23
        consumerProguardFiles("proguard-rules.pro")
    }
}

// Configured through `extensions` rather than a `kotlin { }` block, because the
// Kotlin plugin is applied imperatively above and so has no type-safe accessor.
// The extension may not exist yet: with AGP 9 and android.builtInKotlin=false the
// Flutter Gradle Plugin applies KGP to this subproject after the script is evaluated.
fun configureKotlin() {
    extensions.configure(KotlinAndroidProjectExtension::class.java) {
        compilerOptions {
            jvmTarget = JvmTarget.JVM_17
        }
    }
}
if (extensions.findByName("kotlin") != null) {
    configureKotlin()
} else {
    plugins.withId("org.jetbrains.kotlin.android") { configureKotlin() }
}

dependencies {
    // PreppSuite patch: zxing-cpp in place of ML Kit (both the bundled
    // `com.google.mlkit:barcode-scanning` and the Play services variant).
    // ML Kit reports usage to Google on every use; zxing-cpp sends nothing.
    // See third_party/LIESMICH.md.
    implementation("io.github.zxing-cpp:android:2.3.0")

    implementation("androidx.camera:camera-lifecycle:1.6.1")
    implementation("androidx.camera:camera-camera2:1.6.1")
    implementation("org.jetbrains.kotlinx:kotlinx-coroutines-android:1.11.0")
}
