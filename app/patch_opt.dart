import 'dart:io';

void main() {
  final file = File('lib/screens/optimization_screen.dart');
  var content = file.readAsStringSync();
  
  if (!content.contains('import ''../storage_service.dart'';')) {
    content = content.replaceFirst('import ''package:permission_handler/permission_handler.dart'';', 'import ''package:permission_handler/permission_handler.dart'';\nimport ''../storage_service.dart'';');
  }

  // Add _storage, _isAutostartVerified
  content = content.replaceFirst(
    '''  bool _isBatteryOptimized = true;
  bool _isNotifGranted = false;''',
    '''  final _storage = StorageService();
  bool _isBatteryOptimized = true;
  bool _isNotifGranted = false;
  bool _isAutostartVerified = false;'''
  );

  // Update _checkPermissions to fetch autostart
  content = content.replaceFirst(
    '''    final batteryOpt = await Permission.ignoreBatteryOptimizations.isGranted;
    final notif = await Permission.notification.isGranted;

    if (mounted) {
      setState(() {
        _isBatteryOptimized = !batteryOpt; // true if it is currently optimized (which is bad for us)
        _isNotifGranted = notif;
      });
    }''',
    '''    final batteryOpt = await Permission.ignoreBatteryOptimizations.isGranted;
    final notif = await Permission.notification.isGranted;
    final autostart = await _storage.getAutostartVerified();

    if (mounted) {
      setState(() {
        _isBatteryOptimized = !batteryOpt; // true if it is currently optimized (which is bad for us)
        _isNotifGranted = notif;
        _isAutostartVerified = autostart;
      });
    }'''
  );

  // Update _requestAutoStart
  content = content.replaceFirst(
    '''    } catch (e) {
      debugPrint("Aucune activitA© d'autostart trouvA©e ou erreur: \");
    }
  }''',
    '''    } catch (e) {
      debugPrint("Aucune activité d'autostart trouvée ou erreur: \");
    }
    
    // Show dialog to confirm
    if (mounted) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text("Démarrage Automatique"),
          content: const Text("Avez-vous pu activer l'autostart pour AutoRoomzio dans les paramètres qui viennent de s'ouvrir (ou étiez-vous déjà autorisé) ?"),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text("Non / Pas trouvé")),
            ElevatedButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("Oui, c'est fait")),
          ],
        )
      );
      if (confirmed == true) {
        await _storage.saveAutostartVerified(true);
        _checkPermissions();
      }
    }
  }'''
  );

  // Update isOk: null to isOk: _isAutostartVerified
  content = content.replaceFirst(
    '''isOk: null, // We can't definitively check this''',
    '''isOk: _isAutostartVerified,'''
  );
  
  // Replace weird encoding if they exist
  content = content.replaceAll('D\\u00A9marrage Automatique', 'Démarrage Automatique');
  content = content.replaceAll('aprA"s un redAcmarrage', 'après un redémarrage');
  content = content.replaceAll('EmpA\\u00AAche Android', 'Empêche Android');
  content = content.replaceAll('en arriA"re-plan', 'en arrière-plan');

  file.writeAsStringSync(content);
}
