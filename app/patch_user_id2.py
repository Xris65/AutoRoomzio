import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad = "return (here: here, elsewhere: elsewhere, delegated: delegated);"
good = "return (here: here, elsewhere: elsewhere, delegated: delegated, myUserId: foundUserId);"

content = content.replace(bad, good)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)