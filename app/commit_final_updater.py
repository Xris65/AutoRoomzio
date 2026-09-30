import subprocess

subprocess.run(["git", "add", "lib/screens/home_screen.dart"])
subprocess.run(["git", "commit", "-m", "feat(updater): ajout d'une barre de progression (MB) et ajustement des SnackBars"])
subprocess.run(["git", "push", "origin", "version-1.3.1"])