plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    // Two independent bindings to ONNX Runtime end up in this application, and
    // both ship a file called libonnxruntime.so:
    //
    //   * mobile_ocr, through the Java AAR (onnxruntime-android 1.27.0, 28 MB)
    //   * byrsa_restore, through the Dart FFI package (its own build, 14 MB)
    //
    // Gradle refuses to merge them, and — this is the part worth knowing — it
    // only refuses in **release**. The debug build packages them happily, so
    // the failure appears at the exact moment you are trying to ship.
    //
    // `pickFirsts` alone is a trap. Measured: it keeps the Dart package's
    // 14.2 MB build and discards the AAR's 28 MB one, which makes the APK look
    // 13 MB better while leaving mobile_ocr's JNI shim — compiled against
    // 1.27.0 — paired with a different, older library. An APK that got smaller
    // is exactly how that ships.
    //
    // So the choice is made deterministically instead, in the subprojects block
    // of ../build.gradle.kts: the Dart package's copy is dropped at its source
    // and only the AAR's survives. Both bindings then share ONNX Runtime
    // 1.27.0 — the Java shim gets the library it was built against, and the FFI
    // package resolves `libonnxruntime.so` by name and finds the newer one,
    // whose C API is backwards compatible.
    //
    // pickFirsts stays as a safety net for the merge itself. It should never
    // have anything left to choose between.
    packaging {
        jniLibs {
            pickFirsts += "lib/**/libonnxruntime.so"
        }
    }

    namespace = "dev.byrsa.byrsa"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "dev.byrsa.byrsa"
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
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
