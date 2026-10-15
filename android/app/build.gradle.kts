plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

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
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.ragoose.telegrive"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
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
