import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_init = """  void initState() {
    super.initState();
    _checkUpdatesOnStartup();
    _startDownload();
  }"""

good_init = """  void initState() {
    super.initState();
    _startDownload();
  }"""

content = content.replace(bad_init, good_init)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)