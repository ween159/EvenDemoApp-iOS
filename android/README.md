Android quick notes — fixes and install steps

Summary
- This module contains a native library `liblc3.so` built with CMake and packaged into the debug APK.
- Recent fixes applied:
  - `kotlin.incremental=false` in `android/gradle.properties` to avoid Kotlin incremental daemon issues.
  - Activity name fixed to `com.example.demo_ai_even.MainActivity` in the manifest.
  - External native build (CMake) integrated in `android/app/build.gradle` and a `copyCxxLibs` task used to ensure `.so` files are present in `src/main/jniLibs/` when building.

How to build & install (developer machine)
- From project root:
  - `flutter build apk --debug`  # builds the debug APK
  - `adb -s <device-id> install -r -g build/app/outputs/flutter-apk/app-debug.apk`  # reinstall on device

Quick verification on device
- If the app crashes with `UnsatisfiedLinkError: library 'liblc3.so' not found`, check:
  1. Device storage: `adb -s <device-id> shell df -h /data` — low `/data` space can cause partial installs and missing native libs.
  2. Pull the installed APK and list libs: `adb -s <device-id> shell pm path com.evenrealities.demo` -> `adb -s <device-id> pull <path> pulled_app.apk` -> `unzip -l pulled_app.apk | findstr "liblc3.so"`

JNI notes
- Kotlin wrapper: `android/app/src/main/kotlin/com/example/demo_ai_even/cpp/Cpp.kt` calls `System.loadLibrary("lc3")` and declares these externals: `decodeLC3`, `rnNoise`, `createRNNoiseState`, `destroyRNNoiseState`.
- Native implementation: `android/app/src/main/cpp/liblc3.cpp` exports JNI symbols matching the Kotlin names (e.g. `Java_com_example_demo_1ai_1even_cpp_Cpp_decodeLC3`).

Optional hardening
- Move `System.loadLibrary("lc3")` from the Kotlin `object` initializer to `MainActivity.onCreate()` to reduce classloader timing issues.
- Add a Gradle verification task to assert presence of `liblc3.so` in `build/intermediates/merged_native_libs/` during CI.

If you want, I can:
- Move the `System.loadLibrary` call into `MainActivity.onCreate` for extra robustness.
- Add a simple Gradle verification task that fails the build if `liblc3.so` isn't packaged.
