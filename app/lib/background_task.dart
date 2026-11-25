import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';
import 'api_service.dart';
import 'notification_service.dart';
import 'services/automation_engine.dart';
import 'storage_service.dart';

/// Runs the automated booking process for configured rules/days and pending requests
/// within the 13-day window, applying pre-flight conflict guards and holiday suspension.
/// Returns the number of newly reserved desks.
///
/// When [enforceAutomationEnabled] is true (as in [callbackDispatcher]), the run
/// aborts immediately and returns 0 if `automation_enabled` is false in storage.
/// Defaults to `false` to preserve compatibility with standalone unit/integration tests
/// that exercise the booking engine directly without setting `automation_enabled`.
Future<int> runBackgroundBookingAutomation({
  RoomzApiService? apiService,
  StorageService? storageService,
  DateTime? nowOverride,
  bool enforceAutomationEnabled = false,
}) async {
  final result = await AutomationEngine.run(
    apiService: apiService,
    storageService: storageService,
    nowOverride: nowOverride,
    enforceAutomationEnabled: enforceAutomationEnabled,
  );
  return result.newlyBookedCount;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask(
    (String task, Map<String, dynamic>? inputData) async {
      debugPrint("🚀 Background task started: $task");
      final storage = StorageService();
      await storage.reloadFromDisk();
      try {
        final result = await AutomationEngine.run(
          storageService: storage,
          enforceAutomationEnabled: true,
        );

        final notifService = NotificationService();
        if (result.newlyBookedCount > 0) {
          if (await storage.getNotifySuccess()) {
            await notifService.showNotification(
              title: 'Réservation réussie',
              body:
                  'AutoRoomzio vient de réserver ${result.newlyBookedCount} bureau(x) pour vous.',
            );
          }
        } else if (result.failedAttemptsCount > 0) {
          if (await storage.getNotifyFailure()) {
            await notifService.showNotification(
              title: 'Échec de réservation',
              body:
                  'AutoRoomzio n\'a pas pu réserver ${result.failedAttemptsCount} créneau(x) demandé(s).',
            );
          }
        }
        return true;
      } catch (e) {
        debugPrint("❌ Background task error: $e");
        try {
          if (await storage.getNotifyFailure()) {
            final notifService = NotificationService();
            await notifService.showNotification(
              title: 'Échec de l\'automatisation',
              body:
                  'Une erreur est survenue lors de la réservation automatique.',
            );
          }
        } catch (_) {}
        return false;
      }
    },
  );
}
