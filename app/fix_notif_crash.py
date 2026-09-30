import re

with open('lib/notification_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

content = content.replace("AndroidInitializationSettings('@drawable/ic_notification')", "AndroidInitializationSettings('ic_notification')")

with open('lib/notification_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)