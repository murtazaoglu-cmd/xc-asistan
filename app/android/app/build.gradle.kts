import java.util.Properties

plugins {
    id("com.android.application")
    // Flutter Gradle eklentisi, Android ve Kotlin eklentilerinden sonra uygulanmalı.
    id("dev.flutter.flutter-gradle-plugin")
}

// Release imzası: android/key.properties (git'e GİRMEZ). Dosya yoksa debug imzasına düşer,
// böylece anahtar deposu olmayan makinede de derleme yapılabilir (ama dağıtılmamalı).
val keyProps = Properties()
val keyPropsFile = rootProject.file("key.properties")
val hasReleaseKey = keyPropsFile.exists()
if (hasReleaseKey) {
    keyPropsFile.inputStream().use { keyProps.load(it) }
}

android {
    namespace = "tr.com.controlx.asistan"
    // flutter_local_notifications ve receive_sharing_intent compileSdk 37 ister (platform otomatik kurulur).
    compileSdk = maxOf(flutter.compileSdkVersion, 37)
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
        // flutter_local_notifications zamanlanmış bildirimler için gerektirir.
        isCoreLibraryDesugaringEnabled = true
    }

    defaultConfig {
        applicationId = "tr.com.controlx.asistan"
        minSdk = 24 // local_auth (SDK 24+), flutter_secure_storage (23+), flutter_local_notifications (24)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (hasReleaseKey) {
            create("release") {
                storeFile = file(keyProps.getProperty("storeFile"))
                storePassword = keyProps.getProperty("storePassword")
                keyAlias = keyProps.getProperty("keyAlias")
                keyPassword = keyProps.getProperty("keyPassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (hasReleaseKey) {
                signingConfigs.getByName("release")
            } else {
                signingConfigs.getByName("debug")
            }
        }
    }
}

dependencies {
    coreLibraryDesugaring("com.android.tools:desugar_jdk_libs:2.1.5")
}

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
