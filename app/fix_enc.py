import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Fix encoding issues that were introduced
content = content.replace('Mise Ã  jour disponible ðŸŽ‰', 'Mise à jour disponible 🎉')
content = content.replace('Mise Ã\x82Â\xa0 jour disponible ðŸŽ‰', 'Mise à jour disponible 🎉')
content = content.replace('Une nouvelle version (v) est prÃªte !', 'Une nouvelle version (v) est prête !')
content = content.replace('Une nouvelle version (v) de AutoRoomzio est disponible !\n\nVoulez-vous \nla tÃ©lÃ©charger et l\\'installer maintenant ?', 'Une nouvelle version (v) de AutoRoomzio est disponible !\\n\\nVoulez-vous la télécharger et l\\'installer maintenant ?')
content = content.replace('tÃ©lÃ©charger', 'télécharger')
content = content.replace('Mise Ã  jour', 'Mise à jour')
content = content.replace('Mise Ã jour', 'Mise à jour')
content = content.replace('prÃªte', 'prête')
content = content.replace('ðŸŽ‰', '🎉')
content = content.replace('vÃ©rifier', 'vérifier')
content = content.replace('mises Ã  jour', 'mises à jour')
content = content.replace('AmÃ©liorations', 'Améliorations')
content = content.replace('Ã©', 'é')
content = content.replace('Ã ', 'à')
content = content.replace('Ã', 'à')

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)