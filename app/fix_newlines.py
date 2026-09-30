with open('lib/main.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("debugPrint('Notification init failed: $e\n$stack');", "debugPrint('Notification init failed: $e\\n$stack');")
content = content.replace("debugPrint('Workmanager init failed: $e\n$stack');", "debugPrint('Workmanager init failed: $e\\n$stack');")
content = content.replace("child: Text('CRITICAL STARTUP ERROR:\n$e\n\n$stack', style: const TextStyle(color: Colors.red)),", "child: Text('CRITICAL STARTUP ERROR:\\n$e\\n\\n$stack', style: const TextStyle(color: Colors.red)),")

with open('lib/main.dart', 'w', encoding='utf-8') as f:
    f.write(content)