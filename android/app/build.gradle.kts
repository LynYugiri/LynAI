import java.util.Properties

plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

val keystoreProperties = Properties().apply {
    val keystorePropertiesFile = rootProject.file("key.properties")
    if (keystorePropertiesFile.exists()) {
        keystorePropertiesFile.inputStream().use(::load)
    }
}

fun flutterTargetAbis(): Set<String> {
    // Flutter limits Dart/AOT output through target-platform, but AGP's CMake
    // and JNI packaging do not automatically inherit that filter.
    val targetPlatforms = (findProperty("target-platform") as? String)
        ?.split(',')
        ?.map { it.trim() }
        ?.filter { it.isNotEmpty() }
        ?: return emptySet()

    return targetPlatforms.mapNotNullTo(linkedSetOf()) {
        when (it) {
            "android-arm" -> "armeabi-v7a"
            "android-arm64" -> "arm64-v8a"
            "android-x86" -> "x86"
            "android-x64" -> "x86_64"
            else -> null
        }
    }
}

val targetAbis = flutterTargetAbis()
val androidAbis = setOf("armeabi-v7a", "arm64-v8a", "x86", "x86_64")

android {
    namespace = "com.github.lynyugiri.lynai"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.github.lynyugiri.lynai"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        externalNativeBuild {
            cmake {
                targets += listOf("lynai_tree_sitter")
            }
        }
    }

    externalNativeBuild {
        cmake {
            path = file("../../native/tree_sitter/CMakeLists.txt")
        }
    }

    if (targetAbis.isNotEmpty()) {
        packaging {
            jniLibs {
                // Keep single-architecture release APKs honest: native plugins
                // can otherwise contribute stale or transitive libraries for
                // ABIs that Flutter did not compile libapp.so for.
                excludes += androidAbis
                    .filterNot { it in targetAbis }
                    .map { "lib/$it/**" }
            }
        }
    }

    signingConfigs {
        create("lynai") {
            keyAlias = keystoreProperties["keyAlias"] as String
            keyPassword = keystoreProperties["keyPassword"] as String
            storeFile = rootProject.file(keystoreProperties["storeFile"] as String)
            storePassword = keystoreProperties["storePassword"] as String
        }
    }

    buildTypes {
        debug {
            signingConfig = signingConfigs.getByName("lynai")
        }

        release {
            signingConfig = signingConfigs.getByName("lynai")
        }
    }
}

flutter {
    source = "../.."
}
