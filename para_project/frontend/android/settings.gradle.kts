pluginManagement {
    val flutterSdkPath =
        run {
            val properties = java.util.Properties()
            val localPropertiesFile = file("local.properties")
            if (localPropertiesFile.exists()) {
                localPropertiesFile.inputStream().use { properties.load(it) }
            }

            val configuredFlutterSdkPath = properties.getProperty("flutter.sdk")
            val fallbackFlutterSdkPath =
                System.getenv("FLUTTER_ROOT") ?: "C:/dev/flutter-sdk"
            val flutterSdkPath =
                when {
                    configuredFlutterSdkPath != null && file(configuredFlutterSdkPath).exists() ->
                        configuredFlutterSdkPath
                    file(fallbackFlutterSdkPath).exists() -> fallbackFlutterSdkPath
                    else -> configuredFlutterSdkPath
                }

            require(flutterSdkPath != null) {
                "flutter.sdk not set in local.properties and no fallback Flutter SDK path was found"
            }
            require(file(flutterSdkPath).exists()) {
                "Flutter SDK path does not exist: $flutterSdkPath"
            }
            flutterSdkPath
        }

    includeBuild("$flutterSdkPath/packages/flutter_tools/gradle")

    repositories {
        google()
        mavenCentral()
        gradlePluginPortal()
    }
}

plugins {
    id("dev.flutter.flutter-plugin-loader") version "1.0.0"
    id("com.android.application") version "8.11.1" apply false
    id("org.jetbrains.kotlin.android") version "2.2.20" apply false
}

include(":app")
