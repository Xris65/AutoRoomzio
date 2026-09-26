# AutoRoomzio 🏢✨

AutoRoomzio est une application mobile intelligente conçue pour automatiser vos réservations de bureau sur la plateforme **MyRoomz**. Fini les oublis et le stress de trouver une place, l'application s'en charge pour vous en tâche de fond !

<p align="center">
  <img src="app/assets/icon.jpg" width="150" alt="AutoRoomzio Icon" style="border-radius:20px"/>
</p>

## 🚀 Fonctionnalités principales

- **Pilote Automatique (Background Task)** : Définissez vos jours de présence réguliers. AutoRoomzio se réveille silencieusement en tâche de fond chaque jour pour réserver votre bureau préféré à l'avance (jusqu'à 13 jours).
- **Calendrier Intégré** : Visualisez d'un coup d'œil vos réservations confirmées (en vert) et vos jours planifiés par l'automate (en bleu). Gérez les exceptions (bloquer/débloquer) facilement d'un simple clic.
- **Connexion Sécurisée et Rapide** : Extraction automatique du token de session depuis votre compte MyRoomz. Vos identifiants ne sont jamais stockés par l'application.
- **Ultra-personnalisable** : 
  - 5 couleurs de thèmes premium et support complet du Mode Sombre.
  - Choisissez votre page de démarrage par défaut (Accueil ou Calendrier).
  - Notifications intelligentes (soyez notifié en cas de succès ou d'échec de réservation).
  - Écrans de chargement dynamiques qui suivent l'état réel des serveurs.

## 🛠 Installation & Compilation

1. **Prérequis** : Vous devez avoir [Flutter](https://docs.flutter.dev/get-started/install) installé sur votre machine (version 3.13+).
2. **Cloner le projet** :
   ```bash
   git clone https://github.com/Xris65/AutoRoomzio.git
   cd AutoRoomzio/app
   ```
3. **Installer les dépendances** :
   ```bash
   flutter pub get
   ```
4. **Générer l'APK** (Android) :
   ```bash
   flutter build apk --release
   ```
   *L'APK sera disponible dans `build/app/outputs/flutter-apk/app-release.apk`.*
   *Note : Un script `build_apk.bat` est également disponible à la racine du projet sous Windows.*

## ⚙️ Configuration (Release Please)

Ce dépôt utilise **GitHub Actions** et **release-please** pour gérer automatiquement les versions.
- À chaque push avec un commit conventionnel (ex: `feat: nouvelle fonctionnalité`, `fix: correction de bug`), une Pull Request est automatiquement générée.
- Lors de la fusion de cette PR, un tag de version est créé, le `CHANGELOG.md` est mis à jour, et l'application est compilée et publiée dans l'onglet **Releases** de GitHub.

> ⚠️ **Important :** Assurez-vous d'avoir coché *"Allow GitHub Actions to create and approve pull requests"* dans *Settings > Actions > General* de ce dépôt.

## 🔒 Sécurité et Vie Privée

- AutoRoomzio ne stocke pas vos mots de passe. L'application récupère directement un jeton d'accès sécurisé en naviguant sur l'interface de MyRoomz via un Webview.
- Toutes les requêtes de réservation sont effectuées localement sur votre téléphone vers l'API officielle de MyRoomz, aucune donnée personnelle n'est interceptée ni stockée sur des serveurs tiers.
