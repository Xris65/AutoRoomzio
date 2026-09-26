import 'dart:io';
import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:android_intent_plus/android_intent.dart';
import '../storage_service.dart';

class OptimizationScreen extends StatefulWidget {
  const OptimizationScreen({super.key});

  @override
  State<OptimizationScreen> createState() => _OptimizationScreenState();
}

class _OptimizationScreenState extends State<OptimizationScreen> with WidgetsBindingObserver {

  bool _isBatteryOptimized = true;
  bool _isNotifGranted = false;
  bool _isAutostartVerified = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _checkPermissions();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _checkPermissions(); // Recheck when returning to app
    }
  }

  Future<void> _checkPermissions() async {
    if (!Platform.isAndroid) return;

    final batteryOpt = await Permission.ignoreBatteryOptimizations.isGranted;
    final notif = await Permission.notification.isGranted;

    if (mounted) {
      setState(() {
        _isBatteryOptimized = !batteryOpt; // true if it is currently optimized (which is bad for us)
        _isNotifGranted = notif;
      });
    }
  }

  Future<void> _requestBattery() async {
    await Permission.ignoreBatteryOptimizations.request();
    _checkPermissions();
  }

  Future<void> _requestNotif() async {
    await Permission.notification.request();
    _checkPermissions();
  }

  Future<void> _requestAutoStart() async {
    if (!Platform.isAndroid) return;
    
    final intents = [
      {'package': 'com.miui.securitycenter', 'component': 'com.miui.permcenter.autostart.AutoStartManagementActivity'},
      {'package': 'com.huawei.systemmanager', 'component': 'com.huawei.systemmanager.optimize.process.ProtectActivity'},
      {'package': 'com.huawei.systemmanager', 'component': 'com.huawei.systemmanager.startupmgr.ui.StartupNormalAppListActivity'},
      {'package': 'com.coloros.safecenter', 'component': 'com.coloros.safecenter.permission.startup.StartupAppListActivity'},
      {'package': 'com.coloros.safecenter', 'component': 'com.coloros.safecenter.startupapp.StartupAppListActivity'},
      {'package': 'com.oppo.safe', 'component': 'com.oppo.safe.permission.startup.StartupAppListActivity'},
      {'package': 'com.iqoo.secure', 'component': 'com.iqoo.secure.ui.phoneoptimize.AddWhiteListActivity'},
      {'package': 'com.vivo.permissionmanager', 'component': 'com.vivo.permissionmanager.activity.BgStartUpManagerActivity'},
      {'package': 'com.asus.mobilemanager', 'component': 'com.asus.mobilemanager.entry.FunctionActivity'},
      {'package': 'com.samsung.android.lool', 'component': 'com.samsung.android.sm.ui.battery.BatteryActivity'},
    ];

    bool launched = false;
    for (final intentDict in intents) {
      try {
        final intent = AndroidIntent(
          action: 'android.intent.action.MAIN',
          package: intentDict['package'],
          componentName: intentDict['component'],
        );
        final canResolve = await intent.canResolveActivity();
        if (canResolve ?? false) {
          await intent.launch();
          launched = true;
          break;
        }
      } catch (e) {
        debugPrint("Failed to launch intent \${intentDict['package']}: \$e");
      }
    }

    if (!launched && mounted) {
      // No OEM autostart menu found → standard Android, no config needed
      setState(() => _isAutostartVerified = true);
      final storage = StorageService();
      await storage.saveAutostartVerified(true);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Votre téléphone ne nécessite pas de configuration d'autostart supplémentaire. ✓"),
          backgroundColor: Colors.green,
          duration: Duration(seconds: 4),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Permissions requises'),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Icon(Icons.settings_suggest, size: 64, color: Colors.indigo),
            const SizedBox(height: 16),
            const Text(
              "Configuration de l'Automatisation",
              style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            const Text(
              "Pour que l'application puisse réserver votre bureau automatiquement en arrière-plan, certaines autorisations sont indispensables sur Android.",
              style: TextStyle(fontSize: 16),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            
            // Batterie
            _PermissionTile(
              title: "Optimisation de batterie",
              description: "Empêche Android de tuer l'application en arrière-plan.",
              isOk: !_isBatteryOptimized,
              onTap: _requestBattery,
              actionLabel: "Désactiver l'optimisation",
            ),
            const SizedBox(height: 16),

            // Autostart
            _PermissionTile(
              title: "Démarrage Automatique",
              description: "Requis (surtout Xiaomi, Huawei, Oppo) pour relancer l'automatisation après un redémarrage.",
              isOk: _isAutostartVerified,
              onTap: _requestAutoStart,
              actionLabel: "Vérifier l'autostart",
            ),
            const SizedBox(height: 16),

            // Notifications
            _PermissionTile(
              title: "Notifications",
              description: "Pour être prévenu(e) du succès ou de l'échec de vos réservations.",
              isOk: _isNotifGranted,
              onTap: _requestNotif,
              actionLabel: "Autoriser",
            ),

            const SizedBox(height: 48),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Terminer', style: TextStyle(fontSize: 18)),
            ),
          ],
        ),
      ),
    );
  }
}

class _PermissionTile extends StatelessWidget {
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
  });

  @override
  Widget build(BuildContext context) {
    Color statusColor;
    IconData statusIcon;

    if (isOk == true) {
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (isOk == false) {
      statusColor = Colors.red;
      statusIcon = Icons.cancel;
    } else {
      statusColor = Colors.orange;
      statusIcon = Icons.warning;
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: statusColor.withOpacity(0.5)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
          ),
          const SizedBox(height: 8),
          Text(description, style: TextStyle(color: Colors.grey.shade700, fontSize: 13)),
          const SizedBox(height: 12),
          if (isOk != true)
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(
                  foregroundColor: statusColor,
                  side: BorderSide(color: statusColor),
                ),
                onPressed: onTap,
                child: Text(actionLabel),
              ),
            ),
        ],
      ),
    );
  }
}


