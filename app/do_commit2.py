import os
import subprocess

commit_msg = """feat(ux): mise en place des transitions fluides entre les onglets

- Mise en place d'un AnimatedSwitcher (Fade + Slide) pour des transitions élégantes entre les écrans.
- Optimisation de la navigation via la barre du bas pour supprimer l'effet de saut brutal.
- Intégration d'un détecteur de balayage intelligent pour conserver la navigation rapide au doigt sans interférer avec le calendrier."""

with open('commit_msg2.txt', 'w', encoding='utf-8') as f:
    f.write(commit_msg)

subprocess.run(["git", "commit", "-F", "commit_msg2.txt"])