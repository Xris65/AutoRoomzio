## [1.5.0] - 2026-10-08

### Nouveautés
- **Web & PC Sync** : Support de la version Web (AutoRoomzio Web) avec un système de couplage par QR Code ultra-rapide depuis l'application PC.
- **Multi-Plateforme** : Unification de l'interface pour supporter simultanément Android, Windows et Web.
- **CI/CD** : Déploiement automatique dual (PROD et RECETTE) sur GitHub Pages selon la branche Git.
- **Portable Windows** : Génération automatique d'une archive .zip sans installation pour Windows à chaque Release.

### Correctifs
- **Sécurité des Tokens** : Sécurisation du flux de transfert des tokens (Kamikaze) pour éviter la révocation de session par l'IDP de MyRoomz lors d'un conflit Web/PC.
- **Favoris Web/Mobile** : Correction d'un bug majeur empêchant les collègues favoris d'apparaître sur le plan 2D au premier démarrage.
- **Routeur Web** : Nettoyage physique de l'URL via l'API History HTML5 pour empêcher la réutilisation de vieux tokens ou des boucles de déconnexion infinies.

# Changelog

Toutes les modifications notables de ce projet seront documentÃ©es dans ce fichier.

## [1.4.2] - 2026-10-06

### Correctifs (Hotfix)
- **Authentification Zombie** : L'application forÃ§ait les utilisateurs Ã  rester dans une session bugguÃ©e ("Action impossible") sans jamais les dÃ©connecter lorsque le serveur d'authentification refusait le jeton de rafraÃ®chissement avec une erreur 400 (Bad Request). L'application gÃ¨re dÃ©sormais correctement les rejets OAuth2 complets et redirige vers l'Ã©cran de connexion.

## [1.4.1] - 2026-10-04

### Correctifs (Hotfix)
- **Authentification** : Correction d'un bug critique qui dÃ©connectait brutalement l'utilisateur et effaÃ§ait sa session lorsque le jeton d'accÃ¨s arrivait Ã  expiration naturelle (Erreur HTTP 401). Le jeton est dÃ©sormais rafraÃ®chi silencieusement en arriÃ¨re-plan Ã  la prochaine action.

## [1.4.0] - 2026-10-03

### NouveautÃ©s
- **RÃ©servation pour un collÃ¨gue** : PossibilitÃ© de rÃ©server manuellement un bureau pour quelqu'un d'autre directement depuis l'application (gÃ¨re intelligemment les collÃ¨gues internes et les invitÃ©s externes).
- **Plan d'Ã©quipe 2D Interactif** : Nouvelle vue "OÃ¹ est mon Ã©quipe ?" permettant de visualiser en direct le placement des collaborateurs sur un plan de l'Ã©tage interactif (avec zoom, dÃ©placement et filtrage).
- **SystÃ¨me de RÃ©servation Ã  l'avance (Automate)** : PossibilitÃ© de placer des rÃ©servations "En attente" pour les dates lointaines. Un automate en arriÃ¨re-plan se chargera de valider la rÃ©servation dÃ¨s que la limite des 13 jours de l'API MyRoomz sera levÃ©e.
- **Gestion AvancÃ©e des Favoris** : Ajout d'un bouton Ã©toile sur l'Ã©cran d'accueil pour gÃ©rer ses collÃ¨gues favoris. Les favoris apparaissent en prioritÃ© dans les rÃ©sultats de recherche et sont mis en Ã©vidence sur le plan 2D.
- **RÃ©glage de l'AccessibilitÃ© (UI Scale)** : Ajout d'une option interne permettant de forcer et de choisir la taille globale de l'interface et des textes, indÃ©pendamment des rÃ©glages parfois trop grands du tÃ©lÃ©phone.

### AmÃ©liorations UX/UI
- **Cadrage Intelligent (Smart Zoom)** : Ã€ l'ouverture de la carte 2D, la camÃ©ra se centre automatiquement avec un lÃ©ger zoom sur votre salle/bureau par dÃ©faut. Lors d'un changement d'Ã©tage, la camÃ©ra effectue un zoom global (Zoom-to-fit) pour afficher tout l'Ã©tage sans se perdre dans le vide.
- **Animations de chargement (Shimmer)** : Remplacement des vieilles roues de chargement par des animations fluides de type "Skeleton/Shimmer". Le plan 2D affiche dÃ©sormais de faux murs architecturaux bien proportionnÃ©s pendant le tÃ©lÃ©chargement des donnÃ©es.
- **LisibilitÃ© du plan** : Agrandissement de la surface des bureaux virtuels. Les initiales illisibles sont remplacÃ©es par le format clair "Nom + 1Ã¨re lettre du prÃ©nom" (ex: DUPONT J.).
- **Filtres intelligents** : Les salles de rÃ©union vides sont dÃ©sormais masquÃ©es par dÃ©faut. Le tri des salles se fait intelligemment par densitÃ© d'occupation, en plaÃ§ant vos favoris en tÃªte de liste.

### Correctifs
- **DÃ©connexion intempestive (Critique)** : RÃ©solution du bug agaÃ§ant qui dÃ©connectait l'utilisateur et dÃ©truisait la session lorsqu'il cliquait trop vite (spam) ou qu'une requÃªte rÃ©seau Ã©chouait. La dÃ©connexion est dÃ©sormais strictement restreinte Ã  l'expiration rÃ©elle du mot de passe (Erreur 401).
- **Perte de l'Ã©tage par dÃ©faut** : Lors d'une expiration de session, l'application mÃ©morise dÃ©sormais votre choix de bÃ¢timent, d'Ã©tage et de bureau par dÃ©faut pour votre prochaine reconnexion.
- **Conflit de dÃ©filement (Scroll)** : Correction de la physique de l'Ã©cran de configuration initiale. La page scrolle normalement pour les Ã©tapes 1 et 2, mais se verrouille lors de l'affichage de la carte 2D pour Ã©viter les conflits tactiles avec le zoom.
- **DÃ©bordements visuels (Overflow)** : RÃ©Ã©criture complÃ¨te de la gÃ©omÃ©trie de la carte pour empÃªcher le chevauchement chaotique des salles et supprimer l'alerte "BOTTOM OVERFLOWED" de Flutter.
- **Sauts d'image (Glitch)** : Suppression du saut brutal de la camÃ©ra lors de la premiÃ¨re interaction tactile avec le plan.
- **SÃ©curitÃ© de RÃ©servation** : L'automate en arriÃ¨re-plan et la rÃ©servation manuelle vÃ©rifient dÃ©sormais si le bureau cible n'est pas dÃ©jÃ  occupÃ© par un tiers avant de lancer la requÃªte.
- **DÃ©masquage des erreurs** : L'application affiche dÃ©sormais la vÃ©ritable raison de l'Ã©chec d'une rÃ©servation (ex: "Vous avez dÃ©jÃ  une rÃ©servation sur ce crÃ©neau") au lieu d'afficher aveuglÃ©ment l'erreur par dÃ©faut des 13 jours.

## [1.3.1] - 2026-09-28

### NouveautÃ©s
- **UI/UX** : Ajout du "Pull-to-Refresh" (Tirer pour rafraÃ®chir) sur l'accueil et le calendrier pour une synchronisation manuelle rapide.
- **UI/UX** : Nouvelles transitions premium (Slide + Fade) entre les onglets pour une expÃ©rience beaucoup plus fluide, sans lag.
- **ParamÃ¨tres** : RÃ©organisation complÃ¨te de la page en catÃ©gories logiques, et possibilitÃ© de masquer les onglets Automate/Statistiques.
- **Navigation** : IntÃ©gration d'un dÃ©tecteur de swipe universel pour changer d'onglet d'un coup de pouce sans interfÃ©rer avec le calendrier.
- **Ã€ propos** : Ajout d'un lien cliquable redirigeant vers le dÃ©pÃ´t GitHub du projet.

## [1.3.0] - 2026-09-27

### NouveautÃ©s
- **Statistiques** : Refonte complÃ¨te de l'onglet "Stats". L'application fait dÃ©sormais la diffÃ©rence entre les rÃ©servations automatiques (faites par l'automate) et manuelles (cliquÃ©es).
- **Statistiques** : Affichage du pourcentage de fidÃ©litÃ© Ã  la place, du nombre moyen de jours de prÃ©sentiel par mois, et du jour favori.
- **UI/UX** : Remplacement de la barre de chargement au sommet de l'Ã©cran par d'Ã©lÃ©gants "Skeleton Loaders" (animations de Shimmer) lors de la synchronisation des rÃ©servations.
- **UI/UX** : Restauration de l'Ã©cran de chargement avec les petites phrases amusantes au lancement de l'application.
- **SÃ©curitÃ©** : Ajout d'une protection "Double appui pour quitter" (appuyez deux fois sur Retour pour fermer l'application depuis l'accueil) afin d'Ã©viter les fermetures accidentelles.

### Correctifs
- **Pipeline (GitHub Actions)** : Correction du script d'extraction des notes de version (Changelog) qui Ã©chouait Ã  cause d'une interprÃ©tation d'expression rÃ©guliÃ¨re, laissant les textes de "Release" vides sur GitHub.

## [1.2.2] - 2026-09-27

### NouveautÃ©s
- **Plan 2D** : Ajout de boutons flottants de zoom (+ / -) en bas Ã  droite pour faciliter la navigation Ã  une main.
- **Permissions** : Images d'instructions visuelles (captures d'Ã©cran MIUI) intÃ©grÃ©es dans les popups d'information pour la Batterie et l'Autostart.
- **Autostart** : Popup de validation manuelle ajoutÃ©e aprÃ¨s l'ouverture du menu systÃ¨me pour s'assurer que l'utilisateur a bien effectuÃ© l'action.

### Correctifs
- **Autostart Xiaomi/Oppo/Huawei** : L'application parvient enfin Ã  forcer l'ouverture du menu natif de dÃ©marrage automatique en contournant les restrictions de visibilitÃ© d'Android 11+.
- **Plan 2D** : Blocage complet du dÃ©filement de la page (`Stepper`) lorsque le plan est affichÃ©, empÃªchant les conflits tactiles et les sauts d'Ã©cran.
- **Plan 2D** : Ajustement de la marge (padding) pour que la carte prenne tout l'espace disponible Ã  gauche.

## [1.2.1] - 2026-09-26

### NouveautÃ©s
- **Permissions** : Le menu d'optimisation de la batterie Ã©coute dÃ©sormais les changements en temps rÃ©el sans nÃ©cessiter de popup manuelle (polling asynchrone).

### Correctifs
- **Plan 2D** : Chargement accÃ©lÃ©rÃ© de la carte via parallÃ©lisation des requÃªtes API (Geometry + Status).
- **Calendrier** : Correction d'un bug d'affichage oÃ¹ dÃ©sactiver la vue globale dÃ©sactivait de maniÃ¨re incorrecte l'affichage des bureaux alternatifs.

## [1.2.0] - 2026-09-26

### NouveautÃ©s
- **Transparence d'Occupation** : Le calendrier affiche maintenant une pastille grise avec le nom complet de la personne qui a "volÃ©" votre place habituelle.
- **Plan 2D Intelligent** : IntÃ©gration de la gÃ©omÃ©trie Map/GeoJSON pour un plan interactif lors de la configuration de votre bureau.
- **Mode Ailleurs** : Support complet des pastilles oranges pour visualiser les rÃ©servations sur un autre bureau (et possibilitÃ© de les annuler d'un clic via l'API).
- **Mode Vacances** : DÃ©clarer des congÃ©s supprime dÃ©sormais automatiquement toutes les rÃ©servations confirmÃ©es sur la pÃ©riode.

### Optimisations
- **Performances RÃ©seau** : Division par 4 du temps de synchronisation grÃ¢ce Ã  un pool de connexions HTTP (Keep-Alive) et au multiplexage TLS.
- **FluiditÃ© UI** : Le calendrier ne recharge les donnÃ©es d'occupation que pour l'horizon strict des 13 prochains jours, Ã©vitant les ralentissements inutiles.

## [1.1.1] - 2026-09-24

### NouveautÃ©s
- **Ã‰cran de Chargement Fun** : Remplacement du spinner basique par un Ã©cran animÃ© avec des messages cycliques qui suit l'Ã©tat rÃ©el des API.
- **Configuration AvancÃ©e** : Nouvelles options dans les paramÃ¨tres pour modifier l'heure d'exÃ©cution de l'automate et la limite de projection (en jours).
- **Gestion des Dates (Bloquer)** : PossibilitÃ© de bloquer manuellement une date spÃ©cifique pour empÃªcher l'automate de rÃ©server ce jour-lÃ .
- **Actions Rapides** : Nouveau menu Bottom Sheet intuitif au clic sur une date du calendrier.

### Correctifs
- **Synchronisation** : L'automate ne synchronise plus inutilement les calendriers en cas de simple retour en arriÃ¨re depuis les paramÃ¨tres.

## [1.1.0] - 2026-09-20

### NouveautÃ©s
- **Refonte Interface** : Nouvelle navigation par onglets (`BottomNavigationBar`) sÃ©parant proprement le Tableau de bord, le Calendrier et les ParamÃ¨tres.
- **Assistant de Configuration (`Stepper`)** : Refonte de la sÃ©lection du bureau (BÃ¢timent > Ã‰tage > Zone > Place) avec barres de recherche pour filtrer les immenses listes.
- **Personnalisation** : Ajout du support complet du Mode Sombre et sÃ©lection parmi 5 thÃ¨mes de couleurs premium.
- **Smart Sync** : L'application scanne et synchronise intelligemment les 14 prochains jours sans spammer l'API de MyRoomz.

### Correctifs
- **API** : Mise Ã  jour des endpoints MyRoomz (`/workspaces/all` et `/buildings`) pour s'aligner sur les changements de leur infrastructure.

## [1.0.0] - 2026-09-15

### Lancement Initial (Refonte Flutter)
- **Migration** : RÃ©Ã©criture complÃ¨te de l'application depuis le script Python original vers une application mobile Flutter (Android).
- **Pilote Automatique** : SystÃ¨me de `Background Fetch` pour exÃ©cuter la rÃ©servation silencieusement en tÃ¢che de fond tous les jours.
- **Authentification SÃ©curisÃ©e** : Connexion via WebView interceptant les tokens OIDC sans jamais stocker les identifiants de l'utilisateur.
- **Calendrier** : Vue liste des prochains jours permettant d'activer ou dÃ©sactiver des jours de prÃ©sence types.

