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

    signingConfigs {
        getByName("debug") {
            keyAlias = "autoroomzio"
            keyPassword = "autoroomzio"
            storeFile = file("autoroomzio.jks")
            storePassword = "autoroomzio"
        }
        create("release") {
            val envKeystorePath = System.getenv("KEYSTORE_PATH")
            val envKeystorePassword = System.getenv("KEYSTORE_PASSWORD")
            val envKeyAlias = System.getenv("KEY_ALIAS")
            val envKeyPassword = System.getenv("KEY_PASSWORD")

            keyAlias = if (!envKeyAlias.isNullOrBlank()) envKeyAlias else "autoroomzio"
            keyPassword = if (!envKeyPassword.isNullOrBlank()) envKeyPassword else "autoroomzio"
            storeFile = file(if (!envKeystorePath.isNullOrBlank()) envKeystorePath else "autoroomzio.jks")
            storePassword = if (!envKeystorePassword.isNullOrBlank()) envKeystorePassword else "autoroomzio"
        }
    }

    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appName"] = "AutoRoomzio (Debug)"
        }
        release {
            signingConfig = signingConfigs.getByName("release")
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
