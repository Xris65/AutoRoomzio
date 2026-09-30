import subprocess

subprocess.run(["git", "add", "-f", "android/app/autoroomzio.jks"])
subprocess.run(["git", "commit", "--amend", "--no-edit"])
subprocess.run(["git", "push", "-f", "origin", "version-1.3.1"])