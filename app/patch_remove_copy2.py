with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

start_idx = -1
end_idx = -1

for i, line in enumerate(lines):
    if "icon: const Icon(Icons.copy)," in line:
        start_idx = i - 1  # Include the IconButton line
    if start_idx != -1 and "Text('JSON copi" in line:
        end_idx = i + 3
        break

if start_idx != -1 and end_idx != -1:
    del lines[start_idx:end_idx]
    with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
        f.writelines(lines)
    print("Replaced!")
else:
    print(f"Failed. start: {start_idx}, end: {end_idx}")