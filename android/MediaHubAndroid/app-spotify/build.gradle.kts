plugins {
    id("com.android.application")
    id("org.jetbrains.kotlin.android")
    id("org.jetbrains.kotlin.plugin.compose")
}
android {
    namespace = "com.mediahub.app.spotify"
    compileSdk = 35
    defaultConfig {
        applicationId = "com.mediahub.spotify"
        minSdk = 26
        targetSdk = 35
        versionCode = 1
        versionName = "9.2.0"
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
    implementation(project(":spotify"))
}
