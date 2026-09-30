import subprocess

def run_cmd(args):
    print(f"Running: {' '.join(args)}")
    subprocess.run(args)

run_cmd(["git", "restore", "android/app/build.gradle.kts", "android/app/src/main/AndroidManifest.xml"])
run_cmd(["git", "checkout", "develop"])
run_cmd(["git", "pull", "origin", "develop"])