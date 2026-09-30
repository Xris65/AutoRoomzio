import re

with open('lib/screens/home_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# Add url_launcher import if not present
if "import 'package:url_launcher/url_launcher.dart';" not in content:
    content = content.replace("import 'package:flutter/material.dart';", "import 'package:flutter/material.dart';\nimport 'package:url_launcher/url_launcher.dart';")

# Find _buildSettingsTab
start_idx = content.find("  Widget _buildSettingsTab() {")
if start_idx != -1:
    content = content[:start_idx] + """  Widget _buildSettingsTab() {
    return ListView(
      key: const PageStorageKey('settings_scroll'),
      padding: const EdgeInsets.all(16),
      children: [
        const Text('Apparence & Personnalisation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              ValueListenableBuilder<ThemeMode>(
                valueListenable: themeNotifier,
                builder: (context, currentMode, _) {
                  final isDark = currentMode == ThemeMode.dark || 
                      (currentMode == ThemeMode.system && MediaQuery.of(context).platformBrightness == Brightness.dark);
                  return SwitchListTile(
                    title: const Text('Mode sombre'),
                    secondary: Icon(isDark ? Icons.dark_mode_rounded : Icons.light_mode_rounded),
                    value: isDark,
                    onChanged: (val) {
                      themeNotifier.value = val ? ThemeMode.dark : ThemeMode.light;
                      _storage.saveThemeModeIndex(val ? 2 : 1);
                    },
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Couleur du thème'),
                leading: const Icon(Icons.color_lens_rounded),
                trailing: _buildStyledDropdown<int>(
                  value: themeColorNotifier.value,
                  onChanged: (val) {
                    if (val != null) {
                      themeColorNotifier.value = val;
                      _storage.saveThemeColorIndex(val);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 0, child: Text('Bleu (par défaut)')),
                    DropdownMenuItem(value: 1, child: Text('Vert')),
                    DropdownMenuItem(value: 2, child: Text('Violet')),
                    DropdownMenuItem(value: 3, child: Text('Orange')),
                    DropdownMenuItem(value: 4, child: Text('Rouge')),
                  ],
                ),
              ),
              const Divider(height: 1),
              ValueListenableBuilder<int>(
                valueListenable: fontNotifier,
                builder: (context, currentFont, _) {
                  return ListTile(
                    title: const Text('Police d\\'écriture'),
                    leading: const Icon(Icons.font_download_rounded),
                    trailing: _buildStyledDropdown<int>(
                      value: currentFont,
                      onChanged: (val) {
                        if (val != null) {
                          fontNotifier.value = val;
                          _storage.saveFontFamilyIndex(val);
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Classique')),
                        DropdownMenuItem(value: 1, child: Text('Moderne (Poppins)')),
                        DropdownMenuItem(value: 2, child: Text('Code (Fira)')),
                      ],
                    ),
                  );
                },
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        const Text('Interface & Navigation', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              FutureBuilder<int>(
                future: _storage.getInitialTab(),
                builder: (context, snapshot) {
                  return ListTile(
                    title: const Text('Page de démarrage'),
                    subtitle: const Text('Onglet affiché à l\\'ouverture', style: TextStyle(fontSize: 12)),
                    leading: const Icon(Icons.home_rounded),
                    trailing: _buildStyledDropdown<int>(
                      value: snapshot.data ?? 0,
                      onChanged: (val) {
                        if (val != null) {
                          _storage.saveInitialTab(val);
                          setState(() {}); // refresh FutureBuilder
                        }
                      },
                      items: const [
                        DropdownMenuItem(value: 0, child: Text('Accueil (par défaut)')),
                        DropdownMenuItem(value: 1, child: Text('Calendrier')),
                        DropdownMenuItem(value: 2, child: Text('Automate')),
                      ],
                    ),
                  );
                }
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Afficher l\\'onglet Automatisation'),
                secondary: const Icon(Icons.auto_awesome),
                value: _showAutomation,
                onChanged: (val) {
                  setState(() {
                    if (val) _currentIndex++; else _currentIndex--;
                    _showAutomation = val;
                    if (!val) {
                      if (_automationEnabled) _toggleAutomation(false);
                    }
                  });
                  _storage.saveShowAutomation(val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Afficher l\\'onglet Statistiques'),
                secondary: const Icon(Icons.insights_rounded),
                value: _showStats,
                onChanged: (val) {
                  setState(() {
                    if (val) _currentIndex++; else _currentIndex--;
                    _showStats = val;
                  });
                  _storage.saveShowStats(val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text("Tirer pour rafraîchir"),
                subtitle: const Text("Actualiser en glissant vers le bas (Accueil, Calendrier)", style: TextStyle(fontSize: 12)),
                secondary: const Icon(Icons.refresh_rounded),
                value: _pullToRefreshEnabled,
                onChanged: (val) {
                  setState(() => _pullToRefreshEnabled = val);
                  _storage.savePullToRefresh(val);
                },
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text('Paramètres de l\\'Accueil', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              ListTile(
                title: const Text('Prévisions à afficher'),
                subtitle: const Text('Nombre de jours de réservations futures affichés', style: TextStyle(fontSize: 12)),
                leading: const Icon(Icons.format_list_numbered),
                trailing: _buildStyledDropdown<int>(
                  value: _projectionsCount,
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _projectionsCount = val);
                      _storage.saveProjectionsCount(val);
                    }
                  },
                  items: const [
                    DropdownMenuItem(value: 2, child: Text('2 jours')),
                    DropdownMenuItem(value: 4, child: Text('4 jours (par défaut)')),
                    DropdownMenuItem(value: 7, child: Text('7 jours')),
                    DropdownMenuItem(value: 13, child: Text('13 jours (Max)')),
                  ],
                ),
              ),
            ],
          ),
        ),

        const SizedBox(height: 24),
        const Text('Paramètres du Calendrier', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Désactiver le week-end'),
                subtitle: const Text('Grise le samedi/dimanche, bloque les réservations', style: TextStyle(fontSize: 12)),
                secondary: const Icon(Icons.weekend_rounded),
                value: _hideWeekends,
                onChanged: (val) {
                  setState(() => _hideWeekends = val);
                  _storage.saveHideWeekends(val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Affichage compact'),
                subtitle: const Text('Réduit les marges pour voir plus d\\'informations', style: TextStyle(fontSize: 12)),
                secondary: const Icon(Icons.view_compact_rounded),
                value: _compactMode,
                onChanged: (val) {
                  setState(() => _compactMode = val);
                  _storage.saveCompactMode(val);
                },
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        const Text('Notifications', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              SwitchListTile(
                title: const Text('Réservations réussies'),
                subtitle: const Text('Être notifié quand l\\'automatisation réserve', style: TextStyle(fontSize: 12)),
                secondary: const Icon(Icons.notifications_active, color: Colors.green),
                value: _notifySuccess,
                onChanged: (val) {
                  setState(() => _notifySuccess = val);
                  _storage.saveNotifySuccess(val);
                },
              ),
              const Divider(height: 1),
              SwitchListTile(
                title: const Text('Échecs de réservation'),
                subtitle: const Text('Être notifié en cas d\\'erreur (ex: plus de place)', style: TextStyle(fontSize: 12)),
                secondary: const Icon(Icons.error_outline, color: Colors.red),
                value: _notifyFailure,
                onChanged: (val) {
                  setState(() => _notifyFailure = val);
                  _storage.saveNotifyFailure(val);
                },
              ),
              const Divider(height: 1),
              ListTile(
                title: const Text('Tester les notifications', style: TextStyle(color: Colors.blue)),
                subtitle: const Text('Envoyer une notification de test', style: TextStyle(fontSize: 12)),
                leading: const Icon(Icons.send_rounded, color: Colors.blue),
                onTap: () async {
                  final notifService = NotificationService();
                  await notifService.showNotification(
                    title: 'AutoRoomzio - Test',
                    body: 'Ceci est une notification de test ! Si tu vois ça, tout fonctionne. 🎉',
                  );
                },
              ),
            ],
          ),
        ),
        
        const SizedBox(height: 24),
        const Text('À propos', style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.lightBlue)),
        const SizedBox(height: 8),
        Card(
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: Theme.of(context).colorScheme.outlineVariant),
          ),
          child: Column(
            children: [
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  return ListTile(
                    leading: const Icon(Icons.info_outline_rounded),
                    title: const Text('Version'),
                    trailing: Text(snapshot.hasData ? snapshot.data!.version : '...'),
                  );
                },
              ),
              const Divider(height: 1),
              ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text('Code Source'),
                subtitle: const Text('Voir le projet sur GitHub', style: TextStyle(fontSize: 12)),
                trailing: const Icon(Icons.open_in_new_rounded, size: 16),
                onTap: () async {
                  final url = Uri.parse('https://github.com/Xris65/AutoRoomzio');
                  if (await canLaunchUrl(url)) {
                    await launchUrl(url);
                  }
                },
              ),
            ],
          ),
        ),
      ],
    );
  }
}
"""

with open('lib/screens/home_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)