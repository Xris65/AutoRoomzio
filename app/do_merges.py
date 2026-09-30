import subprocess
import sys

def run_cmd(args):
    print(f"Running: {' '.join(args)}")
    res = subprocess.run(args, capture_output=True, text=True)
    if res.returncode != 0:
        print(f"Error: {res.stderr}")
        sys.exit(1)
    print(res.stdout)

run_cmd(["git", "fetch", "--all"])

# Merge into develop
run_cmd(["git", "checkout", "develop"])
run_cmd(["git", "pull", "origin", "develop"])
run_cmd(["git", "merge", "version-1.3.1", "-m", "Merge branch 'version-1.3.1' into develop"])
run_cmd(["git", "push", "origin", "develop"])

# Merge into main
run_cmd(["git", "checkout", "main"])
run_cmd(["git", "pull", "origin", "main"])
run_cmd(["git", "merge", "version-1.3.1", "-m", "Merge branch 'version-1.3.1' into main"])
run_cmd(["git", "push", "origin", "main"])

print("All merges completed and pushed!")