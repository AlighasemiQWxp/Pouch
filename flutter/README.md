# Pouch Flutter app

This directory contains Pouch's Android interface and its typed connection to the Rust core in ../rust.

## Set up

Install Flutter, the Android SDK, and the NDK version pinned in android/app/build.gradle.kts. From this directory, run:

    flutter pub get

To launch Pouch on a connected Android device or emulator, run:

    flutter run

## Rust bridge changes

The generated adapters under lib/src/rust expose the application API to Dart. After changing that API, regenerate the bridge from this directory:

    flutter_rust_bridge_codegen generate

Review the generated changes, then build and verify the app manually on an Android device. Do not commit signing keys, local SDK paths, or passwords.
