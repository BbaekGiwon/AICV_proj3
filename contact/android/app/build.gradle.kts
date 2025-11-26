plugins {
    id("com.android.application")
    id("com.google.gms.google-services")
    id("kotlin-android")
    id("dev.flutter.flutter-gradle-plugin")
}

// ✅ TensorFlow Lite 라이브러리 버전 충돌 최종 해결
configurations.all {
    resolutionStrategy {
        // 1. 다른 라이브러리(litert-api)를 공식 tensorflow-lite-api로 강제 대체
        dependencySubstitution {
            substitute(module("com.google.ai.edge.litert:litert-api")).using(module("org.tensorflow:tensorflow-lite-api:2.10.0"))
        }
        // 2. 모든 tensorflow-lite 관련 라이브러리 버전을 하나로 강제 통일
        force("org.tensorflow:tensorflow-lite:2.10.0")
        force("org.tensorflow:tensorflow-lite-gpu:2.10.0")
        force("org.tensorflow:tensorflow-lite-api:2.10.0")
        force("org.tensorflow:tensorflow-lite-support:0.4.2") // 음성 탐지 라이브러리와 호환되는 버전
    }
}

android {
    namespace = "com.example.contact"
    compileSdk = flutter.compileSdkVersion
    ndkVersion = flutter.ndkVersion

    aaptOptions {
        noCompress("tflite", "lite")
    }

    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }

    kotlinOptions {
        jvmTarget = JavaVersion.VERSION_17.toString()
    }

    defaultConfig {
        applicationId = "com.example.contact"
        minSdk = flutter.minSdkVersion
        targetSdk = flutter.targetSdkVersion
        versionCode = flutter.versionCode
        versionName = flutter.versionName
    }

    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("debug")
        }
    }
}

flutter {
    source = "../.."
}

dependencies {
    implementation("org.tensorflow:tensorflow-lite-task-audio:0.4.3")
}
