plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.autoroomzio.app"
    compileSdk = 37
    ndkVersion = flutter.ndkVersion

    compileOptions {
        isCoreLibraryDesugaringEnabled = true
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.autoroomzio.app"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
        manifestPlaceholders["appName"] = "AutoRoomzio"
    }

    val fallbackKeystore = file("autoroomzio.jks")
    val envKeystorePath = System.getenv("KEYSTORE_PATH")?.takeIf { it.isNotBlank() }
    val resolvedReleaseKeystore = envKeystorePath?.let { file(it) }
        ?: fallbackKeystore.takeIf { it.exists() }

    signingConfigs {
        getByName("debug") {
            if (fallbackKeystore.exists()) {
                keyAlias = "autoroomzio"
                keyPassword = "autoroomzio"
                storeFile = fallbackKeystore
                storePassword = "autoroomzio"
            }
        }
        if (resolvedReleaseKeystore != null) {
            create("release") {
                val envKeystorePassword = System.getenv("KEYSTORE_PASSWORD")?.takeIf { it.isNotBlank() }
                val envKeyAlias = System.getenv("KEY_ALIAS")?.takeIf { it.isNotBlank() }
                val envKeyPassword = System.getenv("KEY_PASSWORD")?.takeIf { it.isNotBlank() }

                storeFile = resolvedReleaseKeystore
                storePassword = envKeystorePassword ?: "autoroomzio"
                keyAlias = envKeyAlias ?: "autoroomzio"
                keyPassword = envKeyPassword ?: "autoroomzio"
            }
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appName"] = "AutoRoomzio (Debug)"
        }
        release {
            signingConfig = signingConfigs.findByName("release") ?: signingConfigs.getByName("debug")
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(
                getDefaultProguardFile("proguard-android-optimize.txt"),
                "proguard-rules.pro"
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
}
