import subprocess

subprocess.run(["git", "add", "../CHANGELOG.md"])
subprocess.run(["git", "commit", "-m", "docs: mise a jour du changelog pour la version 1.3.1"])