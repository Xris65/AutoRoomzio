# Changelog

Toutes les modifications notables de ce projet seront documentées dans ce fichier.

## [1.4.2] - 2026-10-06

### Correctifs (Hotfix)
- **Authentification Zombie** : L'application forçait les utilisateurs à rester dans une session bugguée ("Action impossible") sans jamais les déconnecter lorsque le serveur d'authentification refusait le jeton de rafraîchissement avec une erreur 400 (Bad Request). L'application gère désormais correctement les rejets OAuth2 complets et redirige vers l'écran de connexion.

## [1.4.1] - 2026-10-04

### Correctifs (Hotfix)
- **Authentification** : Correction d'un bug critique qui déconnectait brutalement l'utilisateur et effaçait sa session lorsque le jeton d'accès arrivait à expiration naturelle (Erreur HTTP 401). Le jeton est désormais rafraîchi silencieusement en arrière-plan à la prochaine action.

## [1.4.0] - 2026-10-03

### Nouveautés
- **Réservation pour un collègue** : Possibilité de réserver manuellement un bureau pour quelqu'un d'autre directement depuis l'application (gère intelligemment les collègues internes et les invités externes).
- **Plan d'équipe 2D Interactif** : Nouvelle vue "Où est mon équipe ?" permettant de visualiser en direct le placement des collaborateurs sur un plan de l'étage interactif (avec zoom, déplacement et filtrage).
- **Système de Réservation à l'avance (Automate)** : Possibilité de placer des réservations "En attente" pour les dates lointaines. Un automate en arrière-plan se chargera de valider la réservation dès que la limite des 13 jours de l'API MyRoomz sera levée.
- **Gestion Avancée des Favoris** : Ajout d'un bouton étoile sur l'écran d'accueil pour gérer ses collègues favoris. Les favoris apparaissent en priorité dans les résultats de recherche et sont mis en évidence sur le plan 2D.
- **Réglage de l'Accessibilité (UI Scale)** : Ajout d'une option interne permettant de forcer et de choisir la taille globale de l'interface et des textes, indépendamment des réglages parfois trop grands du téléphone.

### Améliorations UX/UI
- **Cadrage Intelligent (Smart Zoom)** : À l'ouverture de la carte 2D, la caméra se centre automatiquement avec un léger zoom sur votre salle/bureau par défaut. Lors d'un changement d'étage, la caméra effectue un zoom global (Zoom-to-fit) pour afficher tout l'étage sans se perdre dans le vide.
- **Animations de chargement (Shimmer)** : Remplacement des vieilles roues de chargement par des animations fluides de type "Skeleton/Shimmer". Le plan 2D affiche désormais de faux murs architecturaux bien proportionnés pendant le téléchargement des données.
- **Lisibilité du plan** : Agrandissement de la surface des bureaux virtuels. Les initiales illisibles sont remplacées par le format clair "Nom + 1ère lettre du prénom" (ex: DUPONT J.).
- **Filtres intelligents** : Les salles de réunion vides sont désormais masquées par défaut. Le tri des salles se fait intelligemment par densité d'occupation, en plaçant vos favoris en tête de liste.

### Correctifs
- **Déconnexion intempestive (Critique)** : Résolution du bug agaçant qui déconnectait l'utilisateur et détruisait la session lorsqu'il cliquait trop vite (spam) ou qu'une requête réseau échouait. La déconnexion est désormais strictement restreinte à l'expiration réelle du mot de passe (Erreur 401).
- **Perte de l'étage par défaut** : Lors d'une expiration de session, l'application mémorise désormais votre choix de bâtiment, d'étage et de bureau par défaut pour votre prochaine reconnexion.
- **Conflit de défilement (Scroll)** : Correction de la physique de l'écran de configuration initiale. La page scrolle normalement pour les étapes 1 et 2, mais se verrouille lors de l'affichage de la carte 2D pour éviter les conflits tactiles avec le zoom.
- **Débordements visuels (Overflow)** : Réécriture complète de la géométrie de la carte pour empêcher le chevauchement chaotique des salles et supprimer l'alerte "BOTTOM OVERFLOWED" de Flutter.
- **Sauts d'image (Glitch)** : Suppression du saut brutal de la caméra lors de la première interaction tactile avec le plan.
- **Sécurité de Réservation** : L'automate en arrière-plan et la réservation manuelle vérifient désormais si le bureau cible n'est pas déjà occupé par un tiers avant de lancer la requête.
- **Démasquage des erreurs** : L'application affiche désormais la véritable raison de l'échec d'une réservation (ex: "Vous avez déjà une réservation sur ce créneau") au lieu d'afficher aveuglément l'erreur par défaut des 13 jours.

## [1.3.1] - 2026-09-28

### Nouveautés
- **UI/UX** : Ajout du "Pull-to-Refresh" (Tirer pour rafraîchir) sur l'accueil et le calendrier pour une synchronisation manuelle rapide.
- **UI/UX** : Nouvelles transitions premium (Slide + Fade) entre les onglets pour une expérience beaucoup plus fluide, sans lag.
- **Paramètres** : Réorganisation complète de la page en catégories logiques, et possibilité de masquer les onglets Automate/Statistiques.
- **Navigation** : Intégration d'un détecteur de swipe universel pour changer d'onglet d'un coup de pouce sans interférer avec le calendrier.
- **À propos** : Ajout d'un lien cliquable redirigeant vers le dépôt GitHub du projet.

## [1.3.0] - 2026-09-27

### Nouveautés
- **Statistiques** : Refonte complète de l'onglet "Stats". L'application fait désormais la différence entre les réservations automatiques (faites par l'automate) et manuelles (cliquées).
- **Statistiques** : Affichage du pourcentage de fidélité à la place, du nombre moyen de jours de présentiel par mois, et du jour favori.
- **UI/UX** : Remplacement de la barre de chargement au sommet de l'écran par d'élégants "Skeleton Loaders" (animations de Shimmer) lors de la synchronisation des réservations.
- **UI/UX** : Restauration de l'écran de chargement avec les petites phrases amusantes au lancement de l'application.
- **Sécurité** : Ajout d'une protection "Double appui pour quitter" (appuyez deux fois sur Retour pour fermer l'application depuis l'accueil) afin d'éviter les fermetures accidentelles.

### Correctifs
- **Pipeline (GitHub Actions)** : Correction du script d'extraction des notes de version (Changelog) qui échouait à cause d'une interprétation d'expression régulière, laissant les textes de "Release" vides sur GitHub.

## [1.2.2] - 2026-09-27

### Nouveautés
- **Plan 2D** : Ajout de boutons flottants de zoom (+ / -) en bas à droite pour faciliter la navigation à une main.
- **Permissions** : Images d'instructions visuelles (captures d'écran MIUI) intégrées dans les popups d'information pour la Batterie et l'Autostart.
- **Autostart** : Popup de validation manuelle ajoutée après l'ouverture du menu système pour s'assurer que l'utilisateur a bien effectué l'action.

### Correctifs
- **Autostart Xiaomi/Oppo/Huawei** : L'application parvient enfin à forcer l'ouverture du menu natif de démarrage automatique en contournant les restrictions de visibilité d'Android 11+.
- **Plan 2D** : Blocage complet du défilement de la page (`Stepper`) lorsque le plan est affiché, empêchant les conflits tactiles et les sauts d'écran.
- **Plan 2D** : Ajustement de la marge (padding) pour que la carte prenne tout l'espace disponible à gauche.

## [1.2.1] - 2026-09-26

### Nouveautés
- **Permissions** : Le menu d'optimisation de la batterie écoute désormais les changements en temps réel sans nécessiter de popup manuelle (polling asynchrone).

### Correctifs
- **Plan 2D** : Chargement accéléré de la carte via parallélisation des requêtes API (Geometry + Status).
- **Calendrier** : Correction d'un bug d'affichage où désactiver la vue globale désactivait de manière incorrecte l'affichage des bureaux alternatifs.

## [1.2.0] - 2026-09-26

### Nouveautés
- **Transparence d'Occupation** : Le calendrier affiche maintenant une pastille grise avec le nom complet de la personne qui a "volé" votre place habituelle.
- **Plan 2D Intelligent** : Intégration de la géométrie Map/GeoJSON pour un plan interactif lors de la configuration de votre bureau.
- **Mode Ailleurs** : Support complet des pastilles oranges pour visualiser les réservations sur un autre bureau (et possibilité de les annuler d'un clic via l'API).
- **Mode Vacances** : Déclarer des congés supprime désormais automatiquement toutes les réservations confirmées sur la période.

### Optimisations
- **Performances Réseau** : Division par 4 du temps de synchronisation grâce à un pool de connexions HTTP (Keep-Alive) et au multiplexage TLS.
- **Fluidité UI** : Le calendrier ne recharge les données d'occupation que pour l'horizon strict des 13 prochains jours, évitant les ralentissements inutiles.

## [1.1.1] - 2026-09-24

### Nouveautés
- **Écran de Chargement Fun** : Remplacement du spinner basique par un écran animé avec des messages cycliques qui suit l'état réel des API.
- **Configuration Avancée** : Nouvelles options dans les paramètres pour modifier l'heure d'exécution de l'automate et la limite de projection (en jours).
- **Gestion des Dates (Bloquer)** : Possibilité de bloquer manuellement une date spécifique pour empêcher l'automate de réserver ce jour-là.
- **Actions Rapides** : Nouveau menu Bottom Sheet intuitif au clic sur une date du calendrier.

### Correctifs
- **Synchronisation** : L'automate ne synchronise plus inutilement les calendriers en cas de simple retour en arrière depuis les paramètres.

## [1.1.0] - 2026-09-20

### Nouveautés
- **Refonte Interface** : Nouvelle navigation par onglets (`BottomNavigationBar`) séparant proprement le Tableau de bord, le Calendrier et les Paramètres.
- **Assistant de Configuration (`Stepper`)** : Refonte de la sélection du bureau (Bâtiment > Étage > Zone > Place) avec barres de recherche pour filtrer les immenses listes.
- **Personnalisation** : Ajout du support complet du Mode Sombre et sélection parmi 5 thèmes de couleurs premium.
- **Smart Sync** : L'application scanne et synchronise intelligemment les 14 prochains jours sans spammer l'API de MyRoomz.

### Correctifs
- **API** : Mise à jour des endpoints MyRoomz (`/workspaces/all` et `/buildings`) pour s'aligner sur les changements de leur infrastructure.

## [1.0.0] - 2026-09-15

### Lancement Initial (Refonte Flutter)
- **Migration** : Réécriture complète de l'application depuis le script Python original vers une application mobile Flutter (Android).
- **Pilote Automatique** : Système de `Background Fetch` pour exécuter la réservation silencieusement en tâche de fond tous les jours.
- **Authentification Sécurisée** : Connexion via WebView interceptant les tokens OIDC sans jamais stocker les identifiants de l'utilisateur.
- **Calendrier** : Vue liste des prochains jours permettant d'activer ou désactiver des jours de présence types.
