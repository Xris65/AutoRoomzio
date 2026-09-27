import 'package:workmanager/workmanager.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';

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

    final vacations = await storage.getVacations();

    final token = await api.refreshMyToken();
    if (token == null) {
      debugPrint("⚠️ Missing or invalid refresh token, aborting task.");
      return Future.value(true);
    }

    final now = DateTime.now();
    final formatter = DateFormat('yyyy-MM-dd');

    final hideWeekends = await storage.getHideWeekends();
    
    int newlyBookedCount = 0;
    
    // Fetch user's existing bookings — at this desk AND at other desks
    final myBookings = await api.getMyReservations(token, workspaceId);
    final bookedHere = myBookings.here;
    final bookedElsewhere = myBookings.elsewhere.keys.toSet();
    
    // Check next 13 days (max horizon for Roomz)
    for (int i = 1; i <= 13; i++) {
      final targetDate = now.add(Duration(days: i));
      final isWeekend = targetDate.weekday == DateTime.saturday || targetDate.weekday == DateTime.sunday;
      
      if (hideWeekends && isWeekend) continue;
      
            bool isVacation = false;
      for (final v in vacations) {
        final d = DateTime(targetDate.year, targetDate.month, targetDate.day);
        final start = DateTime.parse(v['start']!);
        final end = DateTime.parse(v['end']!);
        final startNorm = DateTime(start.year, start.month, start.day);
        final endNorm = DateTime(end.year, end.month, end.day);
        if (d.compareTo(startNorm) >= 0 && d.compareTo(endNorm) <= 0) {
          isVacation = true;
          break;
        }
      }
      
      if (isVacation) {
        debugPrint("🏖️ Vacation mode is ON for , skipping automation.");
        continue;
      }

      final dateStr = formatter.format(targetDate);

      if (ignoredDates.contains(dateStr)) {
        continue;
      }

      // Skip if already booked elsewhere that day (myRoomz = 1 booking/day max)
      if (bookedElsewhere.contains(dateStr)) {
        debugPrint("📍 Already booked elsewhere on $dateStr, skipping.");
        continue;
      }

      if (daysToBook.contains(targetDate.weekday) || requestedDates.contains(dateStr)) {
        if (bookedHere.contains(dateStr)) {
          newBooked.add(dateStr);
        } else {
          final success = await api.reserveWorkspace(dateStr, token, workspaceId);
          if (success) {
            await storage.recordBookingStat(true);
            newBooked.add(dateStr);
            newlyBookedCount++;
          }
        }
      }
    }
    
    await storage.saveBookedDates(newBooked.toList());
    
    if (newlyBookedCount > 0) {
      final notifService = NotificationService();
      await notifService.showNotification(
        title: 'Réservation réussie',
        body: 'AutoRoomzio vient de réserver $newlyBookedCount bureau(x) pour vous.',
      );
    }
    
    return Future.value(true);
  });
}
