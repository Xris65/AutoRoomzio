awk -v ver="[1.2.2]" '$0 ~ "^## " ver {p=1; next} /^## / {if(p) exit} p' CHANGELOG.md > out1.txt
awk -v ver="## [1.2.2]" 'index($0, ver) == 1 {p=1; next} /^## / {if(p) exit} p' CHANGELOG.md > out2.txt
