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
    
    final requestedDates = await storage.getRequestedDates();
    final bookedDates = await storage.getBookedDates();
    final ignoredDates = await storage.getIgnoredDates();
    Set<String> newBooked = Set.from(bookedDates);

    if (floorId == null || workspaceId == null) {
      debugPrint("⚠️ Missing floor or workspace ID, aborting task.");
      return Future.value(true);
    }

    final vacationMode = await storage.getVacationMode();
    if (vacationMode) {
      debugPrint("🌴 Vacation mode is ON, skipping automation.");
      return Future.value(true);
    }

    final token = await api.refreshMyToken();
    if (token == null) {
      debugPrint("⚠️ Missing or invalid refresh token, aborting task.");
      return Future.value(true);
    }

    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd');

    final bookingHorizon = await storage.getBookingHorizon();
    final hideWeekends = await storage.getHideWeekends();
    
    // Check next days up to bookingHorizon
    for (int i = 1; i <= bookingHorizon; i++) {
      final targetDate = now.add(Duration(days: i));
      final isWeekend = targetDate.weekday == DateTime.saturday || targetDate.weekday == DateTime.sunday;
      
      if (hideWeekends && isWeekend) continue;
      final dateStr = formatter.format(targetDate);

      if (ignoredDates.contains(dateStr)) {
        debugPrint("⛔ User ignored $dateStr. Skip.");
        continue;
      }

      if (daysToBook.contains(targetDate.weekday) || requestedDates.contains(dateStr)) {
        debugPrint("📅 Analyzing $dateStr");
        
        final isReserved = await api.isAlreadyReserved(dateStr, token, floorId, workspaceId);
        if (isReserved) {
          debugPrint("✅ Already reserved (or occupied) for $dateStr. Skip.");
          newBooked.add(dateStr);
        } else {
          debugPrint("🆓 Free! Attempting booking...");
          final success = await api.reserveWorkspace(dateStr, token, workspaceId);
          if (success) {
            newBooked.add(dateStr);
          }
        }
      }
    }
    
    // Save updated booked dates so UI reflects background bookings immediately
    await storage.saveBookedDates(newBooked.toList());
    
    return Future.value(true);
  });
}
