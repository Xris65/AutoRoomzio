import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add variables to state
content = content.replace("bool _automationEnabled = false;", "bool _automationEnabled = false;\n  bool _showAutomation = true;\n  bool _showStats = true;")

# 2. Add loading to _loadData
content = content.replace("final autoTimeMap = await _storage.getAutomationTime();", "final autoTimeMap = await _storage.getAutomationTime();\n    final showAuto = await _storage.getShowAutomation();\n    final showStats = await _storage.getShowStats();")
content = content.replace("_automationEnabled = autoEnabled;", "_automationEnabled = autoEnabled;\n      _showAutomation = showAuto;\n      _showStats = showStats;")

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)