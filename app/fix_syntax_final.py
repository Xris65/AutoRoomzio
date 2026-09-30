import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix string 1
content = content.replace(
    "Text('Téléchargement en cours...\nVeuillez patienter.')",
    r"Text('Téléchargement en cours...\nVeuillez patienter.')"
)

# Fix string 2
content = content.replace(
    "Text('Une nouvelle version (v$latestVersion) de AutoRoomzio est disponible !\n\nVoulez-vous la télécharger et l\\'installer maintenant ?')",
    r"Text('Une nouvelle version (v$latestVersion) de AutoRoomzio est disponible !\n\nVoulez-vous la télécharger et l\'installer maintenant ?')"
)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)