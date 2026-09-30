import subprocess

subprocess.run(["git", "add", "android/app/autoroomzio.jks"])
subprocess.run(["git", "add", "android/app/build.gradle.kts"])
subprocess.run(["git", "add", "pubspec.yaml"])
subprocess.run(["git", "commit", "-m", "build(android): mise en place d'un keystore universel pour debug et release afin de corriger les problemes de mise a jour (App not installed)"])
subprocess.run(["git", "push", "origin", "version-1.3.1"])