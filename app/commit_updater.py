import subprocess

subprocess.run(["git", "add", "lib/screens/home_screen.dart"])
subprocess.run(["git", "add", "pubspec.yaml"])
subprocess.run(["git", "add", "android/app/src/main/AndroidManifest.xml"])
subprocess.run(["git", "commit", "-m", "feat(updater): systeme de mise a jour in-app avec telechargement et installation automatique (open_filex)"])
subprocess.run(["git", "push", "origin", "version-1.3.1"])