plugins {
    id("com.android.application")
    id("kotlin-android")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.v2ray.v2ray"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        isCoreLibraryDesugaringEnabled = true
    }

    kotlinOptions {
        jvmTarget = "17"
    }

    defaultConfig {
        // TODO: Specify your own unique Application ID (https://developer.android.com/studio/build/application-id.html).
        applicationId = "com.v2ray.v2ray"
        // You can update the following values to match your application needs.
        // For more information, see: https://flutter.dev/to/review-gradle-config.
        minSdk = flutter.minSdkVersion
        targetSdk = 34
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        multiDexEnabled = true
    }
    
    // ABI splits configuration for flutter_v2ray_client
    // This ensures proper native library packaging for different CPU architectures
    splits {
        abi {
            isEnable = true
            reset()
            include("x86_64", "armeabi-v7a", "arm64-v8a")
            isUniversalApk = true
        }
    }

    buildTypes {
        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")
            
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
            )

            // NDK configuration for release builds
            ndk {
                abiFilters.addAll(setOf("x86_64", "armeabi-v7a", "arm64-v8a"))
                debugSymbolLevel = "FULL"
            }
        }
    }

    // Custom APK naming
    applicationVariants.all {
        val variant = this
        if (variant.buildType.name == "release") {
            variant.outputs.all {
                val output = this as com.android.build.gradle.internal.api.BaseVariantOutputImpl
                val baseName = "flaming-cherubim-v${variant.versionName}"
                val currentName = output.name // e.g. "release" or "arm64-v8aRelease"
                
                val abi = when {
                    currentName.contains("arm64", ignoreCase = true) -> "arm64-v8a"
                    currentName.contains("v7a", ignoreCase = true) -> "armeabi-v7a"
                    currentName.contains("x86_64", ignoreCase = true) -> "x86_64"
                    currentName.contains("universal", ignoreCase = true) -> "universal"
                    else -> null
                }
                
                output.outputFileName = if (abi != null) "$baseName-$abi.apk" else "$baseName.apk"
            }
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.4")
}
