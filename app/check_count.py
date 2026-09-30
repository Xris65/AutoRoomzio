with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()
if "if (!wsId.contains('-'))" in content:
    print(f"Found {content.count('if (!wsId.contains(')} times")