import re

with open('../CHANGELOG.md', 'r', encoding='utf-8', errors='replace') as f:
    content = f.read()

# First, remove "# Changelog" and "Toutes les modifications..." if they exist.
content = content.replace("# Changelog\n\nToutes les modifications notables de ce projet seront documentAces dans ce fichier.\n\n", "")
content = content.replace("# Changelog\n\nToutes les modifications notables de ce projet seront documentées dans ce fichier.\n\n", "")

# Clean up encoding issues across the whole file
content = content.replace('o" AjoutAc', 'Nouveautés')
content = content.replace('dY?> CorrigAc', 'Correctifs')
content = content.replace('dYs? OptimisAc', 'Optimisations')
content = content.replace('dYZ% Lancement Initial (Refonte Flutter)', 'Lancement Initial (Refonte Flutter)')

content = content.replace('A"', 'è')
content = content.replace('Ac', 'é')
content = content.replace('A ', 'à ')
content = content.replace('A', 'à')
content = content.replace('A%', 'É')
content = content.replace('A1', 'ù')
content = content.replace('A', 'ê') # sometimes
content = content.replace('A©', 'é')

# Now strip leading whitespace
content = content.strip()

new_header = """# Changelog

Toutes les modifications notables de ce projet seront documentées dans ce fichier.

## [1.3.1] - 2026-09-28

### Nouveautés
- **UI/UX** : Ajout du "Pull-to-Refresh" (Tirer pour rafraîchir) sur l'accueil et le calendrier pour une synchronisation manuelle rapide.
- **UI/UX** : Nouvelles transitions premium (Slide + Fade) entre les onglets pour une expérience beaucoup plus fluide, sans lag.
- **Paramètres** : Réorganisation complète de la page en catégories logiques, et possibilité de masquer les onglets Automate/Statistiques.
- **Navigation** : Intégration d'un détecteur de swipe universel pour changer d'onglet d'un coup de pouce sans interférer avec le calendrier.
- **À propos** : Ajout d'un lien cliquable redirigeant vers le dépôt GitHub du projet.

"""

with open('../CHANGELOG.md', 'w', encoding='utf-8') as f:
    f.write(new_header + content)