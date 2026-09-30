with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    lines = f.readlines()

start = 1000
end = 1045
for i in range(start, end):
    print(f"{i+1}: {lines[i]}", end="")