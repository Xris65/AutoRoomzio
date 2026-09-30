import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

dart_old = """                onTap: () async {
                  final url = Uri.parse('https://github.com/Xris65/AutoRoomzio');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url);
                  }
                },"""
dart_new = """                onTap: () async {
                  final url = Uri.parse('https://github.com/Xris65/AutoRoomzio');
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                },"""
content = content.replace(dart_old, dart_new)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)