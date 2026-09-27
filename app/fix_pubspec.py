import re

with open('pubspec.yaml', 'r', encoding='utf-8') as f:
    content = f.read()

old_assets = """  # To add assets to your application, add an assets section, like this:
  # assets:
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg"""

new_assets = """  # To add assets to your application, add an assets section, like this:
  assets:
    - assets/images/
  #   - images/a_dot_burr.jpeg
  #   - images/a_dot_ham.jpeg"""

content = content.replace(old_assets, new_assets)

with open('pubspec.yaml', 'w', encoding='utf-8') as f:
    f.write(content)