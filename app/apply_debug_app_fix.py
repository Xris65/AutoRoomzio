import re

with open('android/app/build.gradle.kts', 'r', encoding='utf-8') as f:
    content = f.read()

# Replace buildTypes block
old_buildTypes = """    buildTypes {
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }"""
    
new_buildTypes = """    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appName"] = "AutoRoomzio (Debug)"
        }
        release {
            signingConfig = signingConfigs.getByName("release")
        }
    }"""

content = content.replace(old_buildTypes, new_buildTypes)

# Ensure appName placeholder exists in defaultConfig
if 'manifestPlaceholders["appName"]' not in content:
    content = content.replace(
        "versionName = flutter.versionName",
        "versionName = flutter.versionName\n        manifestPlaceholders[\"appName\"] = \"AutoRoomzio\""
    )

with open('android/app/build.gradle.kts', 'w', encoding='utf-8') as f:
    f.write(content)

with open('android/app/src/main/AndroidManifest.xml', 'r', encoding='utf-8') as f:
    manifest = f.read()

manifest = manifest.replace('android:label="AutoRoomzio"', 'android:label="${appName}"')

with open('android/app/src/main/AndroidManifest.xml', 'w', encoding='utf-8') as f:
    f.write(manifest)