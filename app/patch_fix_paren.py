with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i, line in enumerate(lines):
    if "const Text('Mon Calendrier'" in line:
        if lines[i+1].strip() == "),":
            del lines[i+1]
            print("Deleted trailing parenthesis!")
            break

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.writelines(lines)