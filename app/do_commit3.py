import os
import subprocess

commit_msg = """feat(settings): réorganisation des paramètres et ajout des liens externes

- Réorganisation complète de l'onglet Paramètres en catégories logiques (Apparence, Navigation, Accueil, Calendrier).
- Homogénéisation des espacements entre les différentes sections pour une meilleure lisibilité.
- Clarification du vocabulaire utilisé dans l'interface ("encart" devient "onglet").
- Ajout d'un accès direct au code source GitHub dans la section "À propos" via `url_launcher`."""

with open('commit_msg3.txt', 'w', encoding='utf-8') as f:
    f.write(commit_msg)

subprocess.run(["git", "commit", "-F", "commit_msg3.txt"])