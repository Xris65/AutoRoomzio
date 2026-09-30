import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix encoding issues that were introduced
content = content.replace("Mise Ã  jour disponible ðŸŽ‰", "Mise à jour disponible 🎉")
content = content.replace("Une nouvelle version (v$latestVersion) est prÃªte !", "Une nouvelle version (v$latestVersion) est prête !")
content = content.replace("AmÃ©liorations", "Améliorations")
content = content.replace("tÃ©lÃ©charger", "télécharger")
content = content.replace("Mise Ã  jour disponible", "Mise à jour disponible")
content = content.replace("prÃªte", "prête")
content = content.replace("ðŸŽ‰", "🎉")
content = content.replace("A", "à")

# Remove the bad markdown stripping completely
bad_clean = """          String releaseNotes = data['body'] ?? 'Améliorations et corrections diverses.';
          releaseNotes = releaseNotes.replaceAll(RegExp(r'\\*\\*'), '').replaceAll(RegExp(r'###\\s?'), '');"""
good_clean = "          String releaseNotes = data['body'] ?? 'Améliorations et corrections diverses.';"
content = content.replace(bad_clean, good_clean)

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)