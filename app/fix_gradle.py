import re

with open('android/app/build.gradle.kts', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace signingConfigs
new_signing = """    signingConfigs {
        create("release") {
            keyAlias = "autoroomzio"
            keyPassword = "autoroomzio"
            storeFile = file("autoroomzio.jks")
            storePassword = "autoroomzio"
        }
    }

    buildTypes {"""
content = content.replace("    buildTypes {", new_signing)

# Replace the release config
old_release = """        release {
            // TODO: Add your own signing config for the release build.
            // Signing with the debug keys for now, so `flutter run --release` works.
            signingConfig = signingConfigs.getByName("debug")"""

new_release = """        release {
            signingConfig = signingConfigs.getByName("release")"""
content = content.replace(old_release, new_release)

with open('android/app/build.gradle.kts', 'w', encoding='utf-8') as f:
    f.write(content)