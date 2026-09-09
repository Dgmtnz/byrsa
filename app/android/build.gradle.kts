allprojects {
    repositories {
        google()
        mavenCentral()
    }
}

val newBuildDir: Directory =
    rootProject.layout.buildDirectory
        .dir("../../build")
        .get()
rootProject.layout.buildDirectory.value(newBuildDir)

subprojects {
    val newSubprojectBuildDir: Directory = newBuildDir.dir(project.name)
    project.layout.buildDirectory.value(newSubprojectBuildDir)
}
// The `onnxruntime` Dart package pins compileSdkVersion 33, and modern AndroidX
// refuses that:
//
//   Dependency 'androidx.fragment:fragment:1.7.1' requires libraries and
//   applications that depend on it to compile against version 34 or later.
//   :onnxruntime is currently compiled against android-33.
//
// Like the native-library collision it hides behind, this only appears in
// release. Raising a dependency's compileSdk from here is the standard
// workaround for a plugin that has fallen behind, and it is safe: compileSdk
// decides which APIs a library may call, not which devices it runs on, and the
// plugin's own minSdkVersion 21 is untouched.
//
// This has to be registered *before* the evaluationDependsOn below, because
// that one evaluates :app, which makes Flutter evaluate every plugin project —
// and an afterEvaluate registered after that is too late to run at all.
//
// The real fix is one line in the plugin:
// docs/upstream/onnxruntime-flutter-compilesdk.md.
subprojects {
    afterEvaluate {
        if (project.name == "onnxruntime") {
            project.extensions.findByName("android")?.withGroovyBuilder {
                "compileSdkVersion"(36)

                // Drop this package's vendored libonnxruntime.so so it never
                // reaches the merge. mobile_ocr already brings the official
                // AAR's, which is newer (1.27.0) and is the one its JNI shim
                // was built against; the FFI package resolves the library by
                // name at run time and finds it.
                //
                // Deterministic on purpose. Leaving Gradle to pick keeps the
                // *smaller* one and silently pairs the OCR engine with a
                // runtime it was not compiled against.
                "packagingOptions" {
                    "jniLibs" {
                        @Suppress("UNCHECKED_CAST")
                        val current = getProperty("excludes") as Set<String>
                        "setExcludes"(current + "**/libonnxruntime.so")
                    }
                }
            }
        }
    }
}

subprojects {
    project.evaluationDependsOn(":app")
}


tasks.register<Delete>("clean") {
    delete(rootProject.layout.buildDirectory)
}
