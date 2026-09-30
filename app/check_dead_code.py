with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

start = max(0, 1323 - 10)
end = min(len(lines), 1323 + 10)

for i in range(start, end):
    print(f"{i+1}: {lines[i]}", end="")