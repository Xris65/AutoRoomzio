import subprocess
import sys

def run_cmd(args):
    print(f"Running: {' '.join(args)}")
    res = subprocess.run(args, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error: {res.stderr}")
        sys.exit(1)
    print(res.stdout)

run_cmd(["git", "checkout", "develop"])
run_cmd(["git", "add", "android/app/build.gradle.kts"])
run_cmd(["git", "add", "android/app/src/main/AndroidManifest.xml"])
run_cmd(["git", "commit", "-m", "chore(android): separation de la version debug (nom et package differents)"])
run_cmd(["git", "push", "origin", "develop"])
run_cmd(["git", "checkout", "main"]) # go back to main to avoid confusion later

print("All done!")