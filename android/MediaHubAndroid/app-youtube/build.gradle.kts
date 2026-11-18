plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "com.mediahub.app.youtube"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.mediahub.youtube"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "21.46.3"
    }
    compileOptions {
        sourceCompatibility = JavaVersion.VERSION_17
        targetCompatibility = JavaVersion.VERSION_17
    }
    kotlinOptions { jvmTarget = "17" }
    buildFeatures { compose = true }
}
dependencies {
    implementation(project(":core"))
    implementation(project(":youtube"))
}
