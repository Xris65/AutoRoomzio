import os
import subprocess

commit_msg = """feat(ux): implémentation du Pull-to-Refresh et fluidité de la navigation

- Ajout du Pull-to-Refresh sur les onglets Accueil et Calendrier pour synchroniser rapidement les données.
- Ajout d'un paramètre 'Tirer pour rafraîchir' dans les options.
- Refonte de la navigation pour autoriser le swipe manuel sans saut d'index ni clignotement.
- Sauvegarde de la position de scroll de chaque page (Paramètres, Accueil) pour un meilleur confort."""

with open('commit_msg.txt', 'w', encoding='utf-8') as f:
    f.write(commit_msg)

subprocess.run(["git", "commit", "-F", "commit_msg.txt"])