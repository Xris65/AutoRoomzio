with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "onTap: () => Navigator.pop(context, 'cancel_delegation')," in line:
        if ");" in lines[i+1]:
            lines[i+1] = "                      ),\n"
            print("Fixed semicolon!")
            break

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)