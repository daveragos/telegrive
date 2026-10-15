import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// The upload key that signs release builds: its keystore and passwords, from
// the git-ignored android/key.properties. A checkout without that file signs
// release builds with the debug key, so `flutter run --release` still works.
val keyPropertiesFile = rootProject.file("key.properties")
val keyProperties = Properties().apply {
    if (keyPropertiesFile.exists()) keyPropertiesFile.inputStream().use { load(it) }
}

fun keyProperty(name: String): String =
    keyProperties.getProperty(name)?.takeIf { it.isNotBlank() }
        ?: throw GradleException("android/key.properties has no $name")

android {
    namespace = "dev.ragoose.telegrive"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        // flutter_local_notifications uses java.time on older Androids.
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "dev.ragoose.telegrive"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // From pubspec.yaml. A split-per-ABI build adds 1000 × the ABI's
        // number to each APK's version code.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (keyPropertiesFile.exists()) {
            create("release") {
                // Absolute, or relative to android/.
                storeFile = rootProject.file(keyProperty("storeFile"))
                storePassword = keyProperty("storePassword")
                keyAlias = keyProperty("keyAlias")
                keyPassword = keyProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.findByName("release")
                ?: signingConfigs.getByName("debug")
        }
    }

    packaging {
        jniLibs {
            // TDLib is the app's own build in src/main/jniLibs (from
            // tool/build_tdlib_android.sh), aligned for 16 KB pages with
            // OpenSSL linked in. It goes in place of handy_tdlib's
            // libtdjson.so, and handy_tdlib's libcrypto.so and libssl.so stay
            // out, since nothing else loads them.
            pickFirsts += "lib/*/libtdjson.so"
            excludes += listOf("lib/*/libcrypto.so", "lib/*/libssl.so")
        }
    }
}

// TDLib's libtdjson.so for each ABI isn't in git: tool/build_tdlib_android.sh
// builds it. Without it the app would carry handy_tdlib's, which needs the
// libcrypto.so and libssl.so left out above, so the build stops instead.
val tdjson =
    listOf("arm64-v8a", "armeabi-v7a", "x86_64", "x86")
        .map { file("src/main/jniLibs/$it/libtdjson.so") }
tasks.named("preBuild") {
    doFirst {
        val missing = tdjson.filterNot { it.exists() }
        if (missing.isNotEmpty()) {
            throw GradleException(
                "TDLib isn't built for Android: run tool/build_tdlib_android.sh " +
                    "(missing ${missing.joinToString()})",
            )
        }
    }
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
    // Activity results (the scanner, the camera, picking a phone folder) and
    // sharing shortcuts. Pinned to the versions the plugins already resolve,
    // so naming them here changes nothing else in the build.
    implementation("androidx.activity:activity-ktx:1.9.0")
    implementation("androidx.core:core-ktx:1.18.0")
    // Google's on-device document scanner. Play services delivers the scanner
    // itself, so the app carries only the thin client.
    implementation("com.google.android.gms:play-services-mlkit-document-scanner:16.0.0")
    // Text recognition for PDF pages that are pictures, such as scans. The
    // Play services edition: the model comes with Play services rather than
    // in the app, which carries only the thin client.
    implementation("com.google.android.gms:play-services-mlkit-text-recognition:19.0.1")
    // Direct share targets on Android 7 to 9, which have no sharing shortcuts
    // of their own.
    implementation("androidx.sharetarget:sharetarget:1.2.0")
}
