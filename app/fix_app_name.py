with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("runApp(const AutoRoomzioApp());", "runApp(const MyApp());")

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)