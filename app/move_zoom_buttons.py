import re

with open('lib/widgets/workspace_map_viewer.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("bottom: 16,\n              left: 16,", "bottom: 16,\n              right: 16,")

with open('lib/widgets/workspace_map_viewer.dart', 'w', encoding='utf-8') as f:
    f.write(content)