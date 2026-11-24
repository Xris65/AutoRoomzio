import 'package:flutter/foundation.dart';
import '../api_service.dart';
import '../holiday_service.dart';
import '../storage_service.dart';
import '../utils/date_helpers.dart';

class AutomationRunResult {
  final int newlyBookedCount;
  final int failedAttemptsCount;
  final bool abortedDueToDisabled;
  final bool abortedDueToMissingAuth;
  final bool abortedDueToMissingConfig;

  const AutomationRunResult({
    this.newlyBookedCount = 0,
    this.failedAttemptsCount = 0,
    this.abortedDueToDisabled = false,
    this.abortedDueToMissingAuth = false,
    this.abortedDueToMissingConfig = false,
  });
}

/// Moteur unifié d'automatisation des réservations sur la fenêtre J+1..J+13.
/// Partagé entre [runBackgroundBookingAutomation] et `HomeScreen._runAutomationNow`.
class AutomationEngine {
  static Future<AutomationRunResult> run({
    RoomzApiService? apiService,
    StorageService? storageService,
    DateTime? nowOverride,
    bool enforceAutomationEnabled = false,
  }) async {
    final api = apiService ?? RoomzApiService();
    final storage = storageService ?? StorageService();

    if (enforceAutomationEnabled && !(await storage.getAutomationEnabled())) {
      debugPrint("⏸️ Automation is disabled, skipping booking run.");
      return const AutomationRunResult(abortedDueToDisabled: true);
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
    final ignoredDates = await storage.getIgnoredDates();
    final updatedRequestedDates = List<String>.from(requestedDates);
    final updatedRequestedWorkspaces = Map<String, String>.from(requestedWorkspaces);
    final updatedRequestedNames = Map<String, String>.from(requestedNames);

    final hasDefaultDesk = workspaceId != null && workspaceId.isNotEmpty;
    if (!hasDefaultDesk && rulesByWeekday.isEmpty && requestedDates.isEmpty) {
      debugPrint("⚠️ Missing workspace ID and no automation rules or pending requests, aborting automation.");
      return const AutomationRunResult(abortedDueToMissingConfig: true);
    }

    final vacations = await storage.getVacations();
    final skipHolidays = await storage.getSkipPublicHolidays();
    final holidayCountry = await storage.getHolidayCountryCode();

    String? token = await api.refreshMyToken();
    token ??= await storage.getRefreshToken();
    if (token == null || token.isEmpty) {
      debugPrint("⚠️ Missing or invalid refresh token, aborting automation.");
      return const AutomationRunResult(abortedDueToMissingAuth: true);
    }

    final now = nowOverride ?? DateTime.now();
    final hideWeekends = await storage.getHideWeekends();

    int newlyBookedCount = 0;
    int failedAttemptsCount = 0;

    // Fetch user's existing bookings — at the default desk AND at any other desk
    final effectiveDefaultWsId = workspaceId ?? '';
    final myBookings = await api.getMyReservations(token, effectiveDefaultWsId);
    final bookedHere = Set<String>.from(myBookings.here);
    final bookedElsewhere = myBookings.elsewhere.keys.toSet();
    final existingUserReservations = await storage.getUserReservationsMap();

    // Prepare list of dates to inspect for occupancy in the next 13 days
    final List<String> targetDates = [];
    for (int i = 1; i <= 13; i++) {
      final d = now.add(Duration(days: i));
      targetDates.add(DateHelpers.formatIsoDate(d));
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
      final isWeekend = targetDate.weekday == DateTime.saturday ||
          targetDate.weekday == DateTime.sunday;

      if (hideWeekends && isWeekend) continue;

      bool isVacation = false;
      final d = DateTime(targetDate.year, targetDate.month, targetDate.day);
      for (final v in vacations) {
        final startRaw = v['start'];
        final endRaw = v['end'];
        if (startRaw == null || endRaw == null) continue;
        final start = DateTime.tryParse(startRaw);
        final end = DateTime.tryParse(endRaw);
        if (start == null || end == null) continue;
        final startNorm = DateTime(start.year, start.month, start.day);
        final endNorm = DateTime(end.year, end.month, end.day);
        if (!d.isBefore(startNorm) && !d.isAfter(endNorm)) {
          isVacation = true;
          break;
        }
      }

      if (isVacation) {
        debugPrint("🏖️ Vacation mode is ON for $targetDate, skipping automation.");
        continue;
      }

      final dateStr = DateHelpers.formatIsoDate(targetDate);

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
        if (hasDefaultDesk && !existingUserReservations.containsKey(dateStr)) {
          await storage.saveUserReservation(
            dateStr,
            workspaceId,
            defaultWorkspaceName ?? workspaceId,
          );
          existingUserReservations[dateStr] = {
            'workspaceId': workspaceId,
            'workspaceName': defaultWorkspaceName ?? workspaceId,
          };
        }
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

        final success = await api.reserveWorkspace(dateStr, token, targetWsId);
        if (success) {
          await storage.recordBookingStat(true);
          await storage.saveUserReservation(
            dateStr,
            targetWsId,
            targetWsName ?? targetWsId,
          );
          if (isTargetingDefault) {
            bookedHere.add(dateStr);
          } else {
            bookedElsewhere.add(dateStr);
          }
          newlyBookedCount++;
          updatedRequestedDates.remove(dateStr);
          updatedRequestedWorkspaces.remove(dateStr);
          updatedRequestedNames.remove(dateStr);
        } else {
          failedAttemptsCount++;
        }
      }
    }

    await storage.saveRequestedDates(updatedRequestedDates);
    await storage.saveRequestedWorkspacesMap(updatedRequestedWorkspaces);
    await storage.saveRequestedWorkspaceNamesMap(updatedRequestedNames);
    await storage.saveLastAutomationRun();

    return AutomationRunResult(
      newlyBookedCount: newlyBookedCount,
      failedAttemptsCount: failedAttemptsCount,
    );
  }
}
