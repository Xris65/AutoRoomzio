import re

with open('../CHANGELOG.md', 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# Let's clean up the misplaced # Changelog
if content.startswith('## [1.3.0]'):
    parts = content.split('# Changelog\n\nToutes les modifications notables de ce projet seront documentAces dans ce fichier.\n\n')
    if len(parts) == 2:
        top_part = parts[0]
        bottom_part = parts[1]
        
        # reconstruct proper
        content = "# Changelog\n\nToutes les modifications notables de ce projet seront documentées dans ce fichier.\n\n"
        content += "## [1.3.1] - 2026-09-28\n\n"
        content += "### 🚀 Ajouté\n"
        content += "- **UI/UX** : Ajout du \"Pull-to-Refresh\" (Tirer pour rafraîchir) sur l'accueil et le calendrier pour une synchronisation manuelle rapide.\n"
        content += "- **UI/UX** : Nouvelles transitions premium (Slide + Fade) entre les onglets pour une expérience beaucoup plus fluide, sans lag.\n"
        content += "- **Paramètres** : Réorganisation complète de la page en catégories logiques, et possibilité de masquer les onglets Automate/Statistiques.\n"
        content += "- **Navigation** : Intégration d'un détecteur de swipe universel pour changer d'onglet d'un coup de pouce sans interférer avec le calendrier.\n"
        content += "- **À propos** : Ajout d'un lien cliquable redirigeant vers le dépôt GitHub du projet.\n\n"
        
        # Add back 1.3.0, replacing broken encoding if needed
        top_part = top_part.replace('o"', '🚀').replace('dY?>', '🐛').replace('A"', 'è').replace('Ac', 'é').replace('A', 'à').replace('A%', 'É').replace('A', 'ù')
        content += top_part
        
        bottom_part = bottom_part.replace('o"', '🚀').replace('dY?>', '🐛').replace('A"', 'è').replace('Ac', 'é').replace('A', 'à').replace('A%', 'É').replace('A', 'ù').replace('dYs?', '⚡')
        content += bottom_part

with open('../CHANGELOG.md', 'w', encoding='utf-8') as f:
    f.write(content)