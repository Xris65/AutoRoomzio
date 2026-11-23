import 'package:workmanager/workmanager.dart';
import 'package:intl/intl.dart';
import 'package:flutter/foundation.dart';
import 'api_service.dart';
import 'holiday_service.dart';
import 'storage_service.dart';
import 'notification_service.dart';

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
  final api = apiService ?? RoomzApiService();
  final storage = storageService ?? StorageService();

  if (enforceAutomationEnabled && !(await storage.getAutomationEnabled())) {
    debugPrint("⏸️ Automation is disabled, skipping background booking run.");
    return 0;
  }

  final floorId = await storage.getFloorId();
  final workspaceId = await storage.getWorkspaceId();
  final defaultWorkspaceName = await storage.getWorkspaceName();
  final daysToBook = await storage.getDays();
  final hasRulesKey = await storage.hasAutomationRules();
  final rules = await storage.getAutomationRules();
  final rulesByWeekday = <int, AutomationRule>{
    for (final r in rules)
      for (final d in r.days) d: r,
  };

  final requestedDates = await storage.getRequestedDates();
  final requestedWorkspaces = await storage.getRequestedWorkspacesMap();
  final requestedNames = await storage.getRequestedWorkspaceNamesMap();
  final bookedDates = await storage.getBookedDates();
  final ignoredDates = await storage.getIgnoredDates();
  final existingElsewhereMap = await storage.getBookedElsewhereMap();
  final Set<String> newBooked = Set.from(bookedDates);
  final Map<String, String> updatedElsewhereMap = Map.from(existingElsewhereMap);
  final List<String> updatedRequestedDates = List.from(requestedDates);
  final Map<String, String> updatedRequestedWorkspaces = Map.from(requestedWorkspaces);
  final Map<String, String> updatedRequestedNames = Map.from(requestedNames);

  final hasDefaultDesk = workspaceId != null && workspaceId.isNotEmpty;
  if (!hasDefaultDesk && rulesByWeekday.isEmpty && requestedDates.isEmpty) {
    debugPrint("⚠️ Missing workspace ID and no automation rules or pending requests, aborting automation.");
    return 0;
  }

  final vacations = await storage.getVacations();
  final skipHolidays = await storage.getSkipPublicHolidays();
  final holidayCountry = await storage.getHolidayCountryCode();

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

  // Fetch user's existing bookings — at the default desk AND at any other desk
  final effectiveDefaultWsId = workspaceId ?? '';
  final myBookings = await api.getMyReservations(token, effectiveDefaultWsId);
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

  // Fetch occupancy to check if the default target desk is occupied by a third party
  Map<String, String> occupiedByOthers = {};
  if (hasDefaultDesk && floorId != null && floorId.isNotEmpty) {
    final myUserId = myBookings.myUserId ?? await api.getCurrentUserId(token);
    final occResult = await api.getWorkspaceOccupancy(
      token,
      workspaceId,
      floorId,
      targetDates,
      myUserId,
      myBookings.elsewhere,
    );
    occupiedByOthers = occResult.occupiedByOthers;
  }

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

    if (skipHolidays &&
        HolidayService.isHoliday(targetDate, countryCode: holidayCountry) &&
        !requestedDates.contains(dateStr)) {
      debugPrint("🎉 Public holiday on $dateStr, skipping automation.");
      continue;
    }

    // Pre-flight Conflict Guard 1:
    // Skip if user already has an active reservation on that date
    if (bookedHere.contains(dateStr)) {
      newBooked.add(dateStr);
      updatedRequestedDates.remove(dateStr);
      updatedRequestedWorkspaces.remove(dateStr);
      updatedRequestedNames.remove(dateStr);
      continue;
    }
    if (bookedElsewhere.contains(dateStr)) {
      debugPrint("📍 User already booked elsewhere on $dateStr, skipping.");
      continue;
    }

    final ruleForDay = rulesByWeekday[targetDate.weekday];
    final shouldBook = requestedDates.contains(dateStr) ||
        ruleForDay != null ||
        (rules.isEmpty && !hasRulesKey && daysToBook.contains(targetDate.weekday));

    if (shouldBook) {
      final targetWsId =
          requestedWorkspaces[dateStr] ?? ruleForDay?.workspaceId ?? workspaceId;
      final targetWsName =
          requestedNames[dateStr] ?? ruleForDay?.workspaceName ?? defaultWorkspaceName ?? targetWsId;

      if (targetWsId == null || targetWsId.isEmpty) continue;

      final isTargetingDefault =
          hasDefaultDesk && targetWsId.toLowerCase() == workspaceId.toLowerCase();

      // Pre-flight Conflict Guard 2:
      // Skip if user's default target desk is already occupied by someone else on that date
      if (isTargetingDefault && occupiedByOthers.containsKey(dateStr)) {
        debugPrint("🔒 Target desk is occupied by ${occupiedByOthers[dateStr]} on $dateStr, skipping.");
        continue;
      }

      if (isTargetingDefault && newBooked.contains(dateStr)) {
        continue;
      }

      final success = await api.reserveWorkspace(dateStr, token, targetWsId);
      if (success) {
        await storage.recordBookingStat(true);
        await storage.saveUserReservation(
          dateStr,
          targetWsId,
          targetWsName ?? targetWsId,
        );
        if (isTargetingDefault) {
          newBooked.add(dateStr);
        } else {
          updatedElsewhereMap[dateStr] = targetWsName ?? targetWsId;
        }
        newlyBookedCount++;
        updatedRequestedDates.remove(dateStr);
        updatedRequestedWorkspaces.remove(dateStr);
        updatedRequestedNames.remove(dateStr);
      }
    }
  }

  await storage.saveBookedDates(newBooked.toList());
  await storage.saveBookedElsewhereMap(updatedElsewhereMap);
  await storage.saveRequestedDates(updatedRequestedDates);
  await storage.saveRequestedWorkspacesMap(updatedRequestedWorkspaces);
  await storage.saveRequestedWorkspaceNamesMap(updatedRequestedNames);
  return newlyBookedCount;
}

@pragma('vm:entry-point')
void callbackDispatcher() {
  Workmanager().executeTask((task, inputData) async {
    debugPrint("🚀 Background task started: $task");
    final newlyBookedCount = await runBackgroundBookingAutomation(
      enforceAutomationEnabled: true,
    );

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
