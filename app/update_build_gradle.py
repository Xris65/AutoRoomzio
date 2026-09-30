import re

with open('android/app/build.gradle.kts', 'r', encoding='utf-8') as f:
    content = f.read()

# Add manifestPlaceholders to defaultConfig for safety fallback
if "versionName = flutter.versionName" in content:
    content = content.replace(
        "versionName = flutter.versionName",
        "versionName = flutter.versionName\n        manifestPlaceholders[\"appName\"] = \"AutoRoomzio\""
    )

# Add debug block to buildTypes
debug_block = """    buildTypes {
        getByName("debug") {
            applicationIdSuffix = ".debug"
            manifestPlaceholders["appName"] = "AutoRoomzio (Debug)"
        }
        release {"""

content = content.replace("    buildTypes {\n        release {", debug_block)

with open('android/app/build.gradle.kts', 'w', encoding='utf-8') as f:
    f.write(content)