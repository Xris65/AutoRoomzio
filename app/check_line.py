with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

for i in range(1625, 1645):
    print(f"{i+1}: {lines[i]}", end="")