import re

with open('lib/screens/optimization_screen.dart', 'r', encoding='utf-8') as f:
    content = f.read()

# 1. Add 500ms delay to autostart
old_delay = """    if (!mounted) return;

    if (launched) {
      // Demander confirmation à l'utilisateur s'il l'a bien fait"""
new_delay = """    if (!mounted) return;

    if (launched) {
      // Attendre un peu que le menu système s'ouvre bien par-dessus avant d'afficher la popup
      await Future.delayed(const Duration(milliseconds: 500));
      if (!mounted) return;
      // Demander confirmation à l'utilisateur s'il l'a bien fait"""
content = content.replace(old_delay, new_delay)

# 2. Add infoText to _PermissionTile definition
old_tile_def = """class _PermissionTile extends StatelessWidget {
  final String title;
  final String description;
  final bool? isOk;
  final VoidCallback onTap;
  final String actionLabel;

  const _PermissionTile({
    required this.title,
    required this.description,
    this.isOk,
    required this.onTap,
    required this.actionLabel,
  });"""
new_tile_def = """class _PermissionTile extends StatelessWidget {
  final String title;
  final String description;
  final bool? isOk;
  final VoidCallback onTap;
  final String actionLabel;
  final String? infoText;

  const _PermissionTile({
    super.key,
    required this.title,
    required this.description,
    this.isOk,
    required this.onTap,
    required this.actionLabel,
    this.infoText,
  });"""
content = content.replace(old_tile_def, new_tile_def)

# 3. Add info icon to _PermissionTile build
old_tile_build = """          Row(
            children: [
              Icon(statusIcon, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
            ],
          ),"""
new_tile_build = """          Row(
            children: [
              Icon(statusIcon, color: statusColor),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
              ),
              if (infoText != null)
                IconButton(
                  icon: const Icon(Icons.info_outline, color: Colors.blueGrey),
                  onPressed: () {
                    showDialog(
                      context: context,
                      builder: (ctx) => AlertDialog(
                        title: Text("Info : $title"),
                        content: Text(infoText!),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(ctx),
                            child: const Text("Compris"),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),"""
content = content.replace(old_tile_build, new_tile_build)

# 4. Add infoText to the invocations
old_batt = """            _PermissionTile(
              title: "Optimisation de batterie",
              description: "Empêche Android de tuer l'application en arrière-plan.",
              isOk: !_isBatteryOptimized,
              onTap: _requestBattery,
              actionLabel: "Désactiver l'optimisation",
            ),"""
new_batt = """            _PermissionTile(
              title: "Optimisation de batterie",
              description: "Empêche Android de tuer l'application en arrière-plan.",
              isOk: !_isBatteryOptimized,
              onTap: _requestBattery,
              actionLabel: "Désactiver l'optimisation",
              infoText: "Dans l'écran qui va s'ouvrir, choisissez 'AutoRoomzio' et sélectionnez 'Pas de restriction' ou 'Non optimisée'.\\n\\nC'est indispensable pour que l'application puisse réserver votre place le matin en arrière-plan.",
            ),"""
content = content.replace(old_batt, new_batt)

old_auto = """            _PermissionTile(
              title: "Démarrage Automatique",
              description: "Requis (surtout Xiaomi, Huawei, Oppo) pour relancer l'automatisation après un redémarrage.",
              isOk: _isAutostartVerified,
              onTap: _requestAutoStart,
              actionLabel: "Vérifier l'autostart",
            ),"""
new_auto = """            _PermissionTile(
              title: "Démarrage Automatique",
              description: "Requis (surtout Xiaomi, Huawei, Oppo) pour relancer l'automatisation après un redémarrage.",
              isOk: _isAutostartVerified,
              onTap: _requestAutoStart,
              actionLabel: "Vérifier l'autostart",
              infoText: "Certains téléphones bloquent le lancement des applications après un redémarrage.\\n\\nDans le menu qui va s'ouvrir, cherchez 'AutoRoomzio' et activez l'interrupteur pour l'autoriser à démarrer tout seul.",
            ),"""
content = content.replace(old_auto, new_auto)

with open('lib/screens/optimization_screen.dart', 'w', encoding='utf-8') as f:
    f.write(content)