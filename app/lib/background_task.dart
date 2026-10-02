import 'package:workmanager/workmanager.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';

/// Runs the automated booking process for configured days and pending requests
/// within the 13-day window, applying Hotfix 6 pre-flight conflict guards.
/// Returns the number of newly reserved desks.
Future<int> runBackgroundBookingAutomation({
  RoomzApiService? apiService,
  StorageService? storageService,
  DateTime? nowOverride,
}) async {
  final api = apiService ?? RoomzApiService();
  final storage = storageService ?? StorageService();

  final floorId = await storage.getFloorId();
  final workspaceId = await storage.getWorkspaceId();
  final daysToBook = await storage.getDays();

  final requestedDates = await storage.getRequestedDates();
  final bookedDates = await storage.getBookedDates();
  final ignoredDates = await storage.getIgnoredDates();
  final Set<String> newBooked = Set.from(bookedDates);

  if (floorId == null || workspaceId == null) {
    debugPrint("⚠️ Missing floor or workspace ID, aborting automation.");
    return 0;
  }

  final vacations = await storage.getVacations();

  String? token = await api.refreshMyToken();
  token ??= await storage.getRefreshToken();
  if (token == null || token.isEmpty) {
    debugPrint("⚠️ Missing or invalid refresh token, aborting automation.");
    return 0;
  }

  final now = nowOverride ?? DateTime.now();
  final formatter = DateFormat('yyyy-MM-dd');
  final hideWeekends = await storage.getHideWeekends();

  int newlyBookedCount = 0;

  // Fetch user's existing bookings — at this desk AND at other desks
  final myBookings = await api.getMyReservations(token, workspaceId);
  final bookedHere = myBookings.here;
  final bookedElsewhere = myBookings.elsewhere.keys.toSet();

  // Prepare list of dates to inspect for occupancy in the next 13 days
  final List<String> targetDates = [];
  for (int i = 1; i <= 13; i++) {
    final d = now.add(Duration(days: i));
    targetDates.add(formatter.format(d));
  }
  final todayNorm = DateTime(now.year, now.month, now.day);
  for (final reqStr in requestedDates) {
    final dt = DateTime.tryParse(reqStr);
    if (dt != null) {
      final norm = DateTime(dt.year, dt.month, dt.day);
      final diff = norm.difference(todayNorm).inDays;
      if (diff >= 0 && diff <= 13 && !targetDates.contains(reqStr)) {
        targetDates.add(reqStr);
      }
    }
  }

  // Fetch occupancy to check if the target desk is occupied by a third party
  final myUserId = await api.getCurrentUserId(token);
  final occResult = await api.getWorkspaceOccupancy(
    token,
    workspaceId,
    floorId,
    targetDates,
    myUserId,
    myBookings.elsewhere,
  );
  final occupiedByOthers = occResult.occupiedByOthers;

  // Process next 13 days
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
      debugPrint("🏖️ Vacation mode is ON for $targetDate, skipping automation.");
      continue;
    }

    final dateStr = formatter.format(targetDate);

    if (ignoredDates.contains(dateStr)) continue;

    // Hotfix 6 Pre-flight Conflict Guard 1:
    // Skip if user already has an active reservation elsewhere on that date
    if (bookedElsewhere.contains(dateStr)) {
      debugPrint("📍 User already booked elsewhere on $dateStr, skipping.");
      continue;
    }

    // Hotfix 6 Pre-flight Conflict Guard 2:
    // Skip if user's target desk is already occupied by someone else on that date
    if (occupiedByOthers.containsKey(dateStr)) {
      debugPrint("🔒 Target desk is occupied by ${occupiedByOthers[dateStr]} on $dateStr, skipping.");
      continue;
    }

    // Check if this date should be booked (configured weekday OR pending requested date)
    if (daysToBook.contains(targetDate.weekday) || requestedDates.contains(dateStr)) {
      if (bookedHere.contains(dateStr)) {
        newBooked.add(dateStr);
      } else if (!newBooked.contains(dateStr)) {
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
  return newlyBookedCount;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("🚀 Background task started: $task");
    final newlyBookedCount = await runBackgroundBookingAutomation();

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

