import re

with open('lib/api_service.dart', 'r', encoding='utf-8') as f:
    content = f.read()

bad_loop = r"for \(final b in bookings\) \{"
good_loop = """String? foundUserId;
            for (final b in bookings) {
              if (foundUserId == null && b['creator'] != null && b['creator']['id'] != null) {
                foundUserId = b['creator']['id']?.toString();
              }"""
content = re.sub(bad_loop, good_loop, content)

with open('lib/api_service.dart', 'w', encoding='utf-8') as f:
    f.write(content)