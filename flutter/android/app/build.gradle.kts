import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val signingProperties = Properties()
val signingPropertiesPath = System.getenv("POUCH_SIGNING_PROPERTIES")
if (!signingPropertiesPath.isNullOrBlank()) {
    val signingPropertiesFile = file(signingPropertiesPath)
    require(signingPropertiesFile.isFile) {
        "POUCH_SIGNING_PROPERTIES must point to an existing private properties file."
    }
    signingPropertiesFile.inputStream().use { signingProperties.load(it) }
    for (property in listOf("storeFile", "storePassword", "keyAlias", "keyPassword")) {
        require(!signingProperties.getProperty(property).isNullOrBlank()) {
            "The private signing properties file is missing $property."
        }
    }
    require(file(signingProperties.getProperty("storeFile")).isFile) {
        "The release keystore file does not exist."
    }
}

android {
    namespace = "com.daybook.app"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.daybook.app"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 35
        // Uses the version code from pubspec.yaml. When using split APKs, 1000 * ABI_VERSION
        // is added automatically by Flutter. (https://developer.android.com/studio/build/configure-apk-splits#configure-APK-versions)
        // You can force using the value of versionCode by specifying the `-P force-version-code-ignoring-abi=true`
        // flag during build.
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        create("release") {
            if (!signingPropertiesPath.isNullOrBlank()) {
                storeFile = file(signingProperties.getProperty("storeFile"))
                storePassword = signingProperties.getProperty("storePassword")
                keyAlias = signingProperties.getProperty("keyAlias")
                keyPassword = signingProperties.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
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

tasks.matching { it.name == "validateSigningRelease" }.configureEach {
    doFirst {
        require(!signingPropertiesPath.isNullOrBlank()) {
            "Set POUCH_SIGNING_PROPERTIES to your private signing properties file before building a release."
        }
    }
}
