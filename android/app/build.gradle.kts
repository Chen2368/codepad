plugins {
    id("com.android.application")
    // The Flutter Gradle Plugin must be applied after the Android and Kotlin Gradle plugins.
    id("dev.flutter.flutter-gradle-plugin")
}

android {
    namespace = "com.codepad.codepad"
    compileSdk = flutter.compileSdkVersion

    // 签名：AGP 默认从 %USERPROFILE%\.android\debug.keystore 读取调试签名，
    // 本机该目录不可写（且要求“不碰 C 盘”），所以把调试密钥库放进项目里。
    // 用 keytool 生成，口令沿用 Android 惯例 android / androiddebugkey。
    signingConfigs {
        getByName("debug") {
            storeFile = file("codepad-debug.keystore")
            storePassword = "android"
            keyAlias = "androiddebugkey"
            keyPassword = "android"
        }
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    defaultConfig {
        applicationId = "com.codepad.codepad"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            // 发布前换成正式签名；当前用调试密钥，保证 flutter run --release 可用。
            signingConfig = signingConfigs.getByName("debug")
        }
    }

    // 关键：Phase 3 把 tcc 编译器以 libtcc.so 的形式放在 jniLibs，
    // 必须强制解压到 nativeLibraryDir（该目录可执行），否则新版 AGP 默认
    // 直接从 APK 页面映射，不会产生可执行文件。
    packaging {
        jniLibs {
            useLegacyPackaging = true
        }
    }
}

// NDK 版本由 Flutter 的 Gradle 插件自动注入（3.47 对应 28.2.13676358），
// 这里不要覆盖；本机已把 NDK 装在 E:\renwu\toolchain\android-sdk\ndk\ 下。

kotlin {
    compilerOptions {
        jvmTarget = org.jetbrains.kotlin.gradle.dsl.JvmTarget.JVM_17
    }
}

flutter {
    source = "../.."
}
