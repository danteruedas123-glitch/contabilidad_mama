import java.io.FileInputStream
import java.util.Properties

plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

// Llave de firma del release (como en Foodzy, hallazgo H-05). La llave y sus
// contraseñas viven FUERA del proyecto: android/key.properties (ignorado por
// git) dice dónde está el .jks. Sin ese archivo el release se firma con la
// llave de debug, que es pública, y Gradle lo advierte.
val firmaRelease = Properties().apply {
    val archivo = rootProject.file("key.properties")
    if (archivo.exists()) FileInputStream(archivo).use { load(it) }
}

android {
    namespace = "com.familia.contabilidadmama"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.familia.contabilidadmama"
        // Android 7.0+ (lo exige la huella con local_auth)
        minSdk = maxOf(24, flutter.minSdkVersion)
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    signingConfigs {
        if (!firmaRelease.isEmpty) {
            create("release") {
                keyAlias = firmaRelease.getProperty("keyAlias")
                keyPassword = firmaRelease.getProperty("keyPassword")
                storeFile = file(firmaRelease.getProperty("storeFile"))
                storePassword = firmaRelease.getProperty("storePassword")
            }
        }
    }

    buildTypes {
        release {
            signingConfig = if (firmaRelease.isEmpty) {
                logger.warn("AVISO: falta android/key.properties; el release se firma con la llave de debug.")
                signingConfigs.getByName("debug")
            } else {
                signingConfigs.getByName("release")
            }
            // R8 encoge y ofusca el código Java/Kotlin (hallazgo H-07 de Foodzy).
            // El código Dart se ofusca con: flutter build apk --obfuscate --split-debug-info=...
            isMinifyEnabled = true
            isShrinkResources = true
            proguardFiles(getDefaultProguardFile("proguard-android-optimize.txt"), "proguard-rules.pro")
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
