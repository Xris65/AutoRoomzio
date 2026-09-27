# Changelog

Toutes les modifications notables de ce projet seront documentées dans ce fichier.

## [1.2.2] - 2026-09-27

### Ajouté
- **Plan 2D** : Ajout de boutons flottants de zoom (+ / -) en bas à droite pour faciliter la navigation à une main.
- **Permissions** : Images d'instructions visuelles dans les popups d'information pour la Batterie et l'Autostart.
- **Autostart** : Popup de validation manuelle pour s'assurer que l'utilisateur a bien coché l'option.

### Corrigé
- **Autostart Xiaomi/Oppo/Huawei** : L'application parvient enfin à forcer l'ouverture du menu natif de démarrage automatique en contournant les restrictions de visibilité d'Android 11+.
- **Plan 2D** : Blocage complet du défilement de la page (Stepper) lorsque le plan est affiché, empêchant les conflits tactiles et les sauts d'écran.
- **Plan 2D** : Ajustement de la marge (padding) pour que la carte prenne tout l'espace disponible à gauche.

## [1.2.1] - 2026-09-26

### Ajouté
- **Permissions** : Le menu d'optimisation de la batterie écoute désormais les changements en temps réel sans nécessiter de popup manuelle (polling asynchrone).

## [1.2.0] - 2026-09-26

### Ajouté
- **Transparence d'Occupation** : Le calendrier affiche maintenant une pastille grise avec le nom complet de la personne qui a réservé votre place habituelle.
- **Plan 2D Intelligent** : Intégration de la géométrie Map/GeoJSON pour un plan interactif lors de la configuration de votre bureau.
- **Mode Ailleurs** : Support complet des pastilles oranges pour visualiser les réservations sur un autre bureau (et possibilité de les annuler d'un clic).
- **Mode Vacances** : Déclarer des congés supprime désormais automatiquement toutes les réservations confirmées sur la période.

### Optimisé
- **Performances Réseau** : Division par 4 du temps de synchronisation grâce à un pool de connexions HTTP (Keep-Alive) et au multiplexage TLS.
- **Fluidité UI** : Le calendrier ne recharge les données d'occupation que pour l'horizon strict des 13 prochains jours, évitant les ralentissements au changement de mois.