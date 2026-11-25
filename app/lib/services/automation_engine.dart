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

class _CandidateBooking {
  final String dateStr;
  final String targetWsId;
  final String targetWsName;
  final String? targetFloorId;
  final bool isTargetingDefault;

  const _CandidateBooking({
    required this.dateStr,
    required this.targetWsId,
    required this.targetWsName,
    required this.targetFloorId,
    required this.isTargetingDefault,
  });

  String? get occupancyCacheKey =>
      (targetFloorId != null && targetFloorId!.isNotEmpty)
          ? '${targetFloorId!.toLowerCase()}::${targetWsId.toLowerCase()}'
          : null;
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
    final storage = storageService ?? StorageService();
    final bool ownsApi = apiService == null;
    final api = apiService ?? RoomzApiService(storage: storage);

    try {
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
      final updatedRequestedWorkspaces =
          Map<String, String>.from(requestedWorkspaces);
      final updatedRequestedNames = Map<String, String>.from(requestedNames);

      final hasDefaultDesk = workspaceId != null && workspaceId.isNotEmpty;
      if (!hasDefaultDesk && rulesByWeekday.isEmpty && requestedDates.isEmpty) {
        debugPrint(
          "⚠️ Missing workspace ID and no automation rules or pending requests, aborting automation.",
        );
        return const AutomationRunResult(abortedDueToMissingConfig: true);
      }

      final vacations = await storage.getVacations();
      final skipHolidays = await storage.getSkipPublicHolidays();
      final holidayCountry = await storage.getHolidayCountryCode();

      // Never pass refresh_token as Authorization Bearer token: always obtain a valid access_token.
      final String? token = await api.refreshMyToken();
      if (token == null || token.isEmpty) {
        debugPrint("⚠️ Missing or invalid access token, aborting automation.");
        return const AutomationRunResult(abortedDueToMissingAuth: true);
      }

      final now = nowOverride ?? DateTime.now();
      final today = normalizeLocalDate(now);
      final todayStr = DateHelpers.formatIsoDate(today);
      final hideWeekends = await storage.getHideWeekends();

      int newlyBookedCount = 0;
      int failedAttemptsCount = 0;

      // Fetch user's existing bookings — at the default desk AND at any other desk
      final effectiveDefaultWsId = workspaceId ?? '';
      final myBookings = await api.getMyReservations(token, effectiveDefaultWsId);
      final bookedHere = Set<String>.from(myBookings.here);
      final bookedElsewhere = myBookings.elsewhere.keys.toSet();
      final localBookedDates = (await storage.getBookedDates()).toSet();
      final localElsewhereDates =
          (await storage.getBookedElsewhereDates()).toSet();
      final existingUserReservations = await storage.getUserReservationsMap();

      // Clean stale (< todayStr) and already-booked dates from requestedDates
      final staleOrBookedRequests = <String>[];
      for (final reqStr in updatedRequestedDates) {
        final parsed = DateTime.tryParse(reqStr);
        final isPast = parsed != null
            ? calendarDaysBetween(today, parsed) < 0
            : reqStr.compareTo(todayStr) < 0;
        final isAlreadyBooked = bookedHere.contains(reqStr) ||
            bookedElsewhere.contains(reqStr) ||
            localBookedDates.contains(reqStr) ||
            localElsewhereDates.contains(reqStr);
        if (isPast || isAlreadyBooked) {
          staleOrBookedRequests.add(reqStr);
        }
      }
      for (final reqStr in staleOrBookedRequests) {
        updatedRequestedDates.remove(reqStr);
        updatedRequestedWorkspaces.remove(reqStr);
        updatedRequestedNames.remove(reqStr);
      }

      String? resolveFloorIdForDesk(
        String targetWsId,
        AutomationRule? ruleForDay,
      ) {
        final lowerTarget = targetWsId.toLowerCase();
        if (ruleForDay != null &&
            ruleForDay.workspaceId.toLowerCase() == lowerTarget &&
            ruleForDay.floorId.isNotEmpty) {
          return ruleForDay.floorId;
        }
        for (final r in rules) {
          if (r.workspaceId.toLowerCase() == lowerTarget &&
              r.floorId.isNotEmpty) {
            return r.floorId;
          }
        }
        if (floorId != null && floorId.isNotEmpty) {
          return floorId;
        }
        return null;
      }

      // First pass over J+1..J+13 (anti-DST calendar math):
      // apply calendar/vacation/holiday/Guard-1 filters and collect candidate bookings.
      final candidates = <_CandidateBooking>[];
      final candidateDatesByDeskKey = <String, List<String>>{};

      for (int i = 1; i <= 13; i++) {
        final targetDate = addCalendarDays(today, i);
        final isWeekend = targetDate.weekday == DateTime.saturday ||
            targetDate.weekday == DateTime.sunday;

        if (hideWeekends && isWeekend) continue;

        bool isVacation = false;
        for (final v in vacations) {
          final startRaw = v['start'];
          final endRaw = v['end'];
          if (startRaw == null || endRaw == null) continue;
          final start = DateTime.tryParse(startRaw);
          final end = DateTime.tryParse(endRaw);
          if (start == null || end == null) continue;
          final startNorm = normalizeLocalDate(start);
          final endNorm = normalizeLocalDate(end);
          if (!targetDate.isBefore(startNorm) && !targetDate.isAfter(endNorm)) {
            isVacation = true;
            break;
          }
        }

        if (isVacation) {
          debugPrint(
            "🏖️ Vacation mode is ON for $targetDate, skipping automation.",
          );
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
            existingUserReservations[dateStr] = <String, String>{
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
          updatedRequestedDates.remove(dateStr);
          updatedRequestedWorkspaces.remove(dateStr);
          updatedRequestedNames.remove(dateStr);
          continue;
        }

        final ruleForDay = rulesByWeekday[targetDate.weekday];
        final shouldBook = requestedDates.contains(dateStr) ||
            ruleForDay != null ||
            (rules.isEmpty &&
                !hasRulesKey &&
                daysToBook.contains(targetDate.weekday));

        if (!shouldBook) continue;

        final targetWsId = requestedWorkspaces[dateStr] ??
            ruleForDay?.workspaceId ??
            workspaceId;
        if (targetWsId == null || targetWsId.isEmpty) continue;

        final targetWsName = requestedNames[dateStr] ??
            ruleForDay?.workspaceName ??
            defaultWorkspaceName ??
            targetWsId;
        final isTargetingDefault = hasDefaultDesk &&
            targetWsId.toLowerCase() == workspaceId.toLowerCase();
        final targetFloorId = resolveFloorIdForDesk(targetWsId, ruleForDay);

        final candidate = _CandidateBooking(
          dateStr: dateStr,
          targetWsId: targetWsId,
          targetWsName: targetWsName,
          targetFloorId: targetFloorId,
          isTargetingDefault: isTargetingDefault,
        );
        candidates.add(candidate);

        final occKey = candidate.occupancyCacheKey;
        if (occKey != null) {
          final datesForDesk =
              candidateDatesByDeskKey.putIfAbsent(occKey, () => <String>[]);
          if (!datesForDesk.contains(dateStr)) {
            datesForDesk.add(dateStr);
          }
        }
      }

      // Pre-flight Conflict Guard 2 (extended to ALL targeted desks across rules & default):
      // Session-cached per (floorId, workspaceId) to avoid redundant requests.
      final occupancyByDeskKey = <String, Map<String, String>>{};
      String? resolvedMyUserId = myBookings.myUserId;
      bool userIdResolved = resolvedMyUserId != null;

      Future<Map<String, String>> getOccupiedDatesForCandidate(
        _CandidateBooking candidate,
      ) async {
        final key = candidate.occupancyCacheKey;
        final cFloorId = candidate.targetFloorId;
        if (key == null || cFloorId == null || cFloorId.isEmpty) {
          return const <String, String>{};
        }
        final cached = occupancyByDeskKey[key];
        if (cached != null) {
          return cached;
        }
        if (!userIdResolved) {
          resolvedMyUserId = await api.getCurrentUserId(token);
          userIdResolved = true;
        }
        final datesToCheck =
            candidateDatesByDeskKey[key] ?? <String>[candidate.dateStr];
        final occResult = await api.getWorkspaceOccupancy(
          token,
          candidate.targetWsId,
          cFloorId,
          datesToCheck,
          resolvedMyUserId,
          myBookings.elsewhere,
        );
        occupancyByDeskKey[key] = occResult.occupiedByOthers;
        return occResult.occupiedByOthers;
      }

      for (final candidate in candidates) {
        final dateStr = candidate.dateStr;
        if (bookedHere.contains(dateStr) || bookedElsewhere.contains(dateStr)) {
          continue;
        }

        final occupiedDates = await getOccupiedDatesForCandidate(candidate);
        if (occupiedDates.containsKey(dateStr)) {
          debugPrint(
            "🔒 Target desk ${candidate.targetWsId} is occupied by ${occupiedDates[dateStr]} on $dateStr, skipping.",
          );
          continue;
        }

        final success = await api.reserveWorkspace(
          dateStr,
          token,
          candidate.targetWsId,
        );
        if (success) {
          await storage.recordBookingStat(true);
          await storage.saveUserReservation(
            dateStr,
            candidate.targetWsId,
            candidate.targetWsName,
          );
          if (candidate.isTargetingDefault) {
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

      await storage.saveRequestedDates(updatedRequestedDates);
      await storage.saveRequestedWorkspacesMap(updatedRequestedWorkspaces);
      await storage.saveRequestedWorkspaceNamesMap(updatedRequestedNames);
      await storage.saveLastAutomationRun();

      return AutomationRunResult(
        newlyBookedCount: newlyBookedCount,
        failedAttemptsCount: failedAttemptsCount,
      );
    } finally {
      if (ownsApi) {
        api.close();
      }
    }
  }
}
