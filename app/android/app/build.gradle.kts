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
    // pickFirsts makes the build work by keeping one. It does not make the
    // situation safe: whichever binding does not get its own binary is then
    // calling a library it was not built against. ONNX Runtime's C API is
    // meant to be stable across versions, so this is expected to work, and
    // "expected to work" is not a claim this project makes without a device.
    // See UNVERIFIED.md and DECISIONS.md D-037 for the two real fixes.
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
