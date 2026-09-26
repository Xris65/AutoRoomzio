import 'package:workmanager/workmanager.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'storage_service.dart';

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("🚀 Background task started: $task");
    
    final api = RoomzApiService();
    final storage = StorageService();

    final floorId = await storage.getFloorId();
    final workspaceId = await storage.getWorkspaceId();
    final daysToBook = await storage.getDays();
    
    if (floorId == null || workspaceId == null) {
      debugPrint("⚠️ Missing floor or workspace ID, aborting task.");
      return Future.value(true);
    }

    final token = await api.refreshMyToken();
    if (token == null) {
      debugPrint("⚠️ Missing or invalid refresh token, aborting task.");
      return Future.value(true);
    }

    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd');

    // Check next 14 days
    for (int i = 1; i <= 14; i++) {
      final targetDate = now.add(Duration(days: i));
      if (daysToBook.contains(targetDate.weekday)) {
        final dateStr = formatter.format(targetDate);
        debugPrint("📅 Analyzing $dateStr");
        
        final isReserved = await api.isAlreadyReserved(dateStr, token, floorId, workspaceId);
        if (isReserved) {
          debugPrint("✅ Already reserved (or occupied) for $dateStr. Skip.");
        } else {
          debugPrint("🆓 Free! Attempting booking...");
          await api.reserveWorkspace(dateStr, token, workspaceId);
        }
      }
    }
    
    return Future.value(true);
  });
}
