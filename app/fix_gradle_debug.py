import re

with open('android/app/build.gradle.kts', 'r', encoding='utf-8') as f:
    content = f.read()

new_signing = """    signingConfigs {
        getByName("debug") {
            keyAlias = "autoroomzio"
            keyPassword = "autoroomzio"
            storeFile = file("autoroomzio.jks")
            storePassword = "autoroomzio"
        }
        create("release") {"""
content = content.replace('    signingConfigs {\n        create("release") {', new_signing)

with open('android/app/build.gradle.kts', 'w', encoding='utf-8') as f:
    f.write(content)