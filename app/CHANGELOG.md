# Changelog

## [1.3.2](https://github.com/Xris65/AutoRoomzio/compare/auto_roomzio-v1.3.0...auto_roomzio-v1.3.2) (2026-10-01)

### Nouveautés & UX
* **Délégations MyRoomz** : Intégration des réservations déléguées sur le calendrier et la page d'accueil (couleur violette).
* **Affichage des Bureaux** : Affichage du vrai nom du bureau de vos collègues (ex: DS-BORD-1-18-D) lors d'une délégation au lieu de 'Autre bureau'.
* **Indicateurs Multiples** : Le calendrier affiche désormais plusieurs petits points de couleur (jusqu'à 3) sous une même date pour refléter des statuts combinés (ex: votre délégation + votre propre réservation + occupation par un tiers).
* **Statistiques Historiques** : Les statistiques (jour favori, moyenne par mois, fidélité) sont désormais calculées sur l'intégralité de l'historique et sont 100% exactes, plutôt que de se limiter à la fenêtre de 13 jours.
* **Performances** : Le chargement des statistiques est désormais asynchrone, accélérant drastiquement le démarrage de l'application.

### Corrections de Bugs
* **Conflit d'annulation** : Correction d'un bug critique où l'annulation d'une place réservée 'Ailleurs' supprimait accidentellement une délégation faite le même jour.
* **Blocage de réservation** : Résolution d'un problème empêchant de réserver son propre bureau s'il y avait une délégation faite sur un bureau différent le même jour.

## [1.3.0](https://github.com/Xris65/AutoRoomzio/compare/auto_roomzio-v1.2.2...auto_roomzio-v1.3.0) (2026-09-27)



### Nouveautés & UX

* **Onglet Statistiques** : Ajout d'un onglet dédié au suivi de votre activité (réservations, moyenne de présentiel et fidélité).

* **Navigation fluide** : Le passage entre les onglets via le menu du bas est désormais instantané pour éviter les saccades visuelles.

* **Chargement Shimmer** : Remplacement du spinner de chargement par un effet skeleton élégant et non-bloquant.

* **Infobulles Stylisées** : Un clic sur une statistique affiche désormais un panneau détaillé et animé au design premium.

* **Icône de Notification** : Intégration d'une icône vectorielle sur-mesure parfaitement adaptée à la barre d'état Android.

* **Testeur d'alertes** : Ajout d'un bouton dédié dans les paramètres pour tester le bon fonctionnement de vos notifications.



### Corrections de Bugs

* **Blocage du Calendrier** : Résolution du bug empêchant de réserver à nouveau une date fraîchement annulée.

* **Compteur Manuel** : Correction d'un crash Android silencieux qui bloquait l'incrémentation des statistiques manuelles.

* **Synchronisation du Cache** : Les statistiques se mettent désormais à jour instantanément après une action de l'automate.





## [1.1.0](https://github.com/Xris65/AutoRoomzio/compare/auto_roomzio-v1.0.0...auto_roomzio-v1.1.0) (2026-09-26)





### Features



* add '(par défaut)' tags to dropdown default options in settings for clarity ([4c03fab](https://github.com/Xris65/AutoRoomzio/commit/4c03fab5aa9936fdaf9530d8ab0d51543111dd45))

* add advanced customization options in Settings (Theme color, Auto-sync on startup, Configurable projections limit) ([93f7799](https://github.com/Xris65/AutoRoomzio/commit/93f7799e879da9b91f95a5b9330861bb01a25279))

* add beautiful generated app icon for AutoRoomzio ([0256262](https://github.com/Xris65/AutoRoomzio/commit/025626233e42f1181555279b6b07b4a3a53264ae))

* add capability to block/ignore specific dates from automation via calendar ([4d0918c](https://github.com/Xris65/AutoRoomzio/commit/4d0918cf2276ea81152bd403935f875f8982918b))

* add clear button to quickly reset selected workspace while keeping site in memory ([bb4ed51](https://github.com/Xris65/AutoRoomzio/commit/bb4ed5182c95828c2f8e4881a3a4900ccd4a0da7))

* add global notification preferences and automation execution time settings ([8b2ab88](https://github.com/Xris65/AutoRoomzio/commit/8b2ab889016b1e25e30de7ab35215789d571c836))

* add initial tab selection and theme mode selector to general settings ([1f28ddc](https://github.com/Xris65/AutoRoomzio/commit/1f28ddc6deb9f0448b5e19a358628955c386f9cf))

* add loading overlay (spinner and grey-out) to the Home tab during quick actions ([544baa2](https://github.com/Xris65/AutoRoomzio/commit/544baa245c690d05d13a3b470022d7c31afa0be0))

* add login screen + dynamic building/floor/workspace discovery ([267be4f](https://github.com/Xris65/AutoRoomzio/commit/267be4fd30c0fd95ba59c1e259ea35e43ec0cb19))

* add quick action buttons (suppress/block) directly on the upcoming reservations list ([5aacb85](https://github.com/Xris65/AutoRoomzio/commit/5aacb853d535cb42b77fb6f229b6bf8ba827d367))

* add search bars to Stepper steps for quick workspace filtering ([827f3fa](https://github.com/Xris65/AutoRoomzio/commit/827f3fa3d70293835c06d19e8d4f884b26def637))

* add settings menu with Dark Mode toggle and make workspace card fully clickable ([c78ab46](https://github.com/Xris65/AutoRoomzio/commit/c78ab46922c5c5519e89b9814f4f7faceb6bb2c2))

* add sync button and cancel reservation dialog to Calendar ([57498f2](https://github.com/Xris65/AutoRoomzio/commit/57498f21e200a0c9b5b7d2ee95516f6d9e84883e))

* add visual overlay and spinner to the Automate tab during manual execution ([6802b04](https://github.com/Xris65/AutoRoomzio/commit/6802b0440ba3bf5e6910060e47994943be8aad64))

* add Windows WebView2 support via webview_windows ([32ff591](https://github.com/Xris65/AutoRoomzio/commit/32ff591501569eefa57ced2ef2f0c7dd81fce88f))

* auto-confirm workspace selection on tap to speed up user flow ([efeaebb](https://github.com/Xris65/AutoRoomzio/commit/efeaebb3140b828e2a279241c5fb5f47a349eb63))

* background task now automatically books pending calendar dates when they enter the 14-day bookable window ([223e5e2](https://github.com/Xris65/AutoRoomzio/commit/223e5e2061914d30431c53de8850492ecbe90fd7))

* connect cancel API to calendar and implement busy state ([702092e](https://github.com/Xris65/AutoRoomzio/commit/702092ef81384d4c0b32d49a5e0910b9fb759d8e))

* group workspaces by room prefix and add 4th Stepper step for seat selection ([557eeea](https://github.com/Xris65/AutoRoomzio/commit/557eeea893c424186839fe0882fd208d8a3e5189))

* implement advance calendar booking with badges for reserved and pending states ([2c51c50](https://github.com/Xris65/AutoRoomzio/commit/2c51c50cd705bcbed972f1b425043e4cba94c113))

* implement smart calendar sync by scanning next 14 days + requested dates ([67f2cab](https://github.com/Xris65/AutoRoomzio/commit/67f2cab569c5b5df719ad7c533c2076bff492299))

* lock calendar UI during sync and booking operations to prevent spamming ([08b588d](https://github.com/Xris65/AutoRoomzio/commit/08b588d347782ff0f7fcf9ce42877f1ed7a1c792))

* make loading screen text progress dynamically based on actual API sync status instead of a dumb timer ([ec72207](https://github.com/Xris65/AutoRoomzio/commit/ec72207faf806bf9ec541ecd34a67715bca77dc0))

* make startup auto-sync mandatory with loading screen and add red theme color ([a38ba70](https://github.com/Xris65/AutoRoomzio/commit/a38ba70faad34ac422c9dd7129157bbcf24e7761))

* pre-fill Stepper in SetupScreen with user's current workspace selection ([426b49f](https://github.com/Xris65/AutoRoomzio/commit/426b49f013648f2c9112e826e4076fc6c5e8a3fb))

* preserve splash screen animation flow artificially when auto-sync is disabled ([47a50df](https://github.com/Xris65/AutoRoomzio/commit/47a50df62333f6ef62a25576096e3ff792bfb30b))

* re-introduce auto-sync on startup as an optional setting with descriptive label ([b26888f](https://github.com/Xris65/AutoRoomzio/commit/b26888f0d35f9360fc62d0103a0651151e3bf0c2))

* redesign home tab with unified automation switch and upcoming reservations preview ([9077a17](https://github.com/Xris65/AutoRoomzio/commit/9077a177b977d3552fdea7972be00e6a9eaa899f))

* refactor home screen with BottomNavigationBar, adding dedicated tabs for Dashboard, Calendar, and Settings ([ba1a407](https://github.com/Xris65/AutoRoomzio/commit/ba1a407438d0e4fccac841a41fa080b1dc14f620))

* replace custom login with real MyRoomz WebView login ([58007e3](https://github.com/Xris65/AutoRoomzio/commit/58007e33ab9673e69b210076c02fb53c937e0fc5))

* replace standard loading spinner with an animated fun loading screen cycling through thematic messages ([7e18894](https://github.com/Xris65/AutoRoomzio/commit/7e18894cb339cce88e53d22d22d6d382ec8d309f))

* replace sync execution on toggle with an explicit 'Lancer maintenant' button in the automation tab ([54295c8](https://github.com/Xris65/AutoRoomzio/commit/54295c8994d927cdca598de2f524eb265a45314d))

* replace tap-to-cycle logic with an intuitive bottom sheet menu in calendar ([01feeb0](https://github.com/Xris65/AutoRoomzio/commit/01feeb0b5d11fa09c89745f9e08a32e1f714dc0f))

* run automation synchronously in foreground when toggling switch for immediate UX feedback ([439dc31](https://github.com/Xris65/AutoRoomzio/commit/439dc31cce917e842d43b7abb3567764cbcf56e0))

* skip cancellation confirmation popup for pending dates (blue badge) ([2f49745](https://github.com/Xris65/AutoRoomzio/commit/2f49745c37e74c77b611792f929e128e5cde0010))

* smart booking button in bottom sheet to program dates out of the 14-day window without sending API request ([1c76d8b](https://github.com/Xris65/AutoRoomzio/commit/1c76d8b16963ccbcebbd811ad68c2b76487aa4d1))

* split configuration and automation into distinct tabs (Accueil vs Automate) ([deb931e](https://github.com/Xris65/AutoRoomzio/commit/deb931e488e86230acf27bc548f34f1d881abc83))

* trigger an immediate one-off background task run when enabling automation ([ec2a0d3](https://github.com/Xris65/AutoRoomzio/commit/ec2a0d3778ed32fe0f3ea30bf66ad690b70bb31d))

* use Stepper widget for a cleaner, step-by-step workspace selection flow ([aa05a6e](https://github.com/Xris65/AutoRoomzio/commit/aa05a6e2fca4cb5c176f4168a1039addb486f56a))





### Bug Fixes



* adjust booking window constraint to exactly J+13 (13 days) to align with MyRoomz true limits ([8649d93](https://github.com/Xris65/AutoRoomzio/commit/8649d939de1c3f20f0f762103783503bcf250d45))

* cancel action no longer forces date into block state unless explicitly requested ([21e92f1](https://github.com/Xris65/AutoRoomzio/commit/21e92f141391d68af416e58edcbe3a13a37606ff))

* clear WebView cookies and cache on init to prevent auto-login loop after logout ([c7ddd90](https://github.com/Xris65/AutoRoomzio/commit/c7ddd90adf8f9aef10e5b20cb60289a9476b45e8))

* orphaned bookings now correctly appear as Calendrier and do not count towards the 4-day automation projection limit ([51a1f0a](https://github.com/Xris65/AutoRoomzio/commit/51a1f0a8871e6b92cab486d83a155139f9d650e6))

* prevent unnecessary calendar sync when navigating back from workspace selection without making changes ([1d81bef](https://github.com/Xris65/AutoRoomzio/commit/1d81bef563504982b45e4394b8f80275d80a1dd3))

* resolve navigation bug where SetupScreen stacked duplicate HomeScreens instead of popping ([06107a3](https://github.com/Xris65/AutoRoomzio/commit/06107a37d6caddf25c9263c3a5967df1da90ce8c))

* resolve unreadable text contrast for selected items in Dark Mode ([d480676](https://github.com/Xris65/AutoRoomzio/commit/d48067669db58cb78f63f4a47b44401538b2a544))

* restore site state correctly in SetupScreen after workspace is reset ([19c4a3a](https://github.com/Xris65/AutoRoomzio/commit/19c4a3a013e9cf2e08b30f403ab90b4e26998c3b))

* robust OIDC token extraction with retry and loadingState trigger ([1b0fa42](https://github.com/Xris65/AutoRoomzio/commit/1b0fa423e9efd17211e9622af06f407a50414a5c))

* safely parse JSON Lists from API to prevent type cast errors during discovery ([4c2443a](https://github.com/Xris65/AutoRoomzio/commit/4c2443a76c61c4c799c5ec8534273c8bd1b65035))

* suppress MSVC experimental coroutine deprecation error from webview_windows ([cf77319](https://github.com/Xris65/AutoRoomzio/commit/cf77319a10680d0fdae9f1b87e048f03f6026ba0))

* update API endpoint to /buildings for workspace discovery ([d340723](https://github.com/Xris65/AutoRoomzio/commit/d340723986022e8e89423cbf4b6e8221976fb41b))

* update workspace API endpoint to /workspaces/all ([a7d4079](https://github.com/Xris65/AutoRoomzio/commit/a7d4079776e49d0686513f1f68106ceb0bfd1de8))

