pluginManagement {
    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}
dependencyResolutionManagement {
    repositoriesMode.set(RepositoriesMode.FAIL_ON_PROJECT_REPOS)
    repositories {
        google()
        mavenCentral()
    }
}
rootProject.name = "MediaHubAndroid"
include(
    ":core",
    ":youtube",
    ":netflix",
    ":spotify",
    ":app-youtube",
    ":app-netflix",
    ":app-spotify",
    ":app-crossover"
)
