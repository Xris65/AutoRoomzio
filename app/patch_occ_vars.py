import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad2 = r"final Map<String, String> occupied = \{\};\s*final Map<String, String> delegated = \{\};"
good2 = "final Map<String, String> occupied = {};\n    final Map<String, String> delegated = {};\n    final Set<String> delegatedHere = {};\n    final Set<String> delegatedElsewhere = {};"

content = re.sub(bad2, good2, content)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)