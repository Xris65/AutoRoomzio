import subprocess

with open('test_awk.sh', 'w') as f:
    f.write('awk -v ver="[1.2.2]" \'$0 ~ "^## " ver {p=1; next} /^## / {if(p) exit} p\' CHANGELOG.md > out1.txt\n')
    f.write('awk -v ver="## [1.2.2]" \'index($0, ver) == 1 {p=1; next} /^## / {if(p) exit} p\' CHANGELOG.md > out2.txt\n')

# Use python to simulate awk because windows doesn't have it natively
# Actually I don't have awk on windows. Let's just fix the yaml