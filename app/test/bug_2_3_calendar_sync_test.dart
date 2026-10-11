import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/background_task.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('Bug #2 & #3 - StorageService Requested Workspace & Calendar Sync', () {
    test('addRequestedDate and saveRequestedWorkspace persist specific desk and date', () async {
      final storage = StorageService();
      const date = '2026-10-25';
      const deskId = 'ws-other-desk-42';
      const deskName = 'Bureau B42';

      // Initially empty
      expect(await storage.getRequestedDates(), isEmpty);
      expect(await storage.getRequestedWorkspace(date), isNull);

      // Add requested date with specific workspace
      await storage.addRequestedDate(date, workspaceId: deskId, workspaceName: deskName);

      // Verify date is persisted in requested_dates
      final dates = await storage.getRequestedDates();
      expect(dates, contains(date));

      // Verify specific workspace ID and name are associated
      expect(await storage.getRequestedWorkspace(date), equals(deskId));
      expect(await storage.getRequestedWorkspaceName(date), equals(deskName));

      final map = await storage.getRequestedWorkspacesMap();
      expect(map[date], equals(deskId));

      final namesMap = await storage.getRequestedWorkspaceNamesMap();
      expect(namesMap[date], equals(deskName));

      // Remove requested date
      await storage.removeRequestedDate(date);
      expect(await storage.getRequestedDates(), isNot(contains(date)));
      expect(await storage.getRequestedWorkspace(date), isNull);
      expect(await storage.getRequestedWorkspaceName(date), isNull);
    });

    test('toggleRequestedDate toggles presence and associates workspace', () async {
      final storage = StorageService();
      const date = '2026-10-30';
      const deskId = 'ws-toggle-desk';

      await storage.toggleRequestedDate(date, workspaceId: deskId, workspaceName: 'Toggle Desk');
      expect((await storage.getRequestedDates()).contains(date), isTrue);
      expect(await storage.getRequestedWorkspace(date), equals(deskId));

      // Toggle again should remove
      await storage.toggleRequestedDate(date);
      expect((await storage.getRequestedDates()).contains(date), isFalse);
      expect(await storage.getRequestedWorkspace(date), isNull);
    });
  });

  group('Bug #3 - Automation books specific programmed workspace', () {
    test('runBackgroundBookingAutomation reserves programmed other desk (desk B) instead of default desk', () async {
      final storage = StorageService();
      await storage.saveFloorId('fl-1');
      await storage.saveWorkspaceId('ws-default-desk-A');
      await storage.saveRefreshToken('mock-token');

      final now = DateTime(2026, 10, 10);
      const targetDateStr = '2026-10-15'; // 5 days in advance (<= 13)
      const deskB = 'ws-custom-desk-B';

      // User programmed desk B in advance for this date
      await storage.addRequestedDate(targetDateStr, workspaceId: deskB, workspaceName: 'Bureau B');
      await storage.saveDays([]); // No recurring weekdays, only the requested date

      String? bookedWorkspaceId;
      final client = MockClient((req) async {
        if (req.url.path.contains('/oauth/token')) {
          return http.Response(jsonEncode({'access_token': 'new-tok', 'refresh_token': 'new-ref'}), 200);
        }
        if (req.url.path.contains('/users/current/reservations') || req.url.path.contains('/users/current/bookings')) {
          return http.Response(jsonEncode({'bookings': []}), 200);
        }
        if (req.url.path.contains('/occupancy') || req.url.path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (req.url.path.contains('/bookings') && req.method == 'POST') {
          final body = jsonDecode(req.body);
          bookedWorkspaceId = body['workspaceId']?.toString();
          return http.Response(jsonEncode({'id': 'booking-success-123'}), 201);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final count = await runBackgroundBookingAutomation(
        apiService: api,
        storageService: storage,
        nowOverride: now,
      );

      // Successfully booked
      expect(count, equals(1));
      // Must have reserved the specific desk B, NOT default desk A!
      expect(bookedWorkspaceId, equals(deskB));

      // Requested date and workspace must be removed from storage once booked
      final updatedReq = await storage.getRequestedDates();
      expect(updatedReq.contains(targetDateStr), isFalse);
      expect(await storage.getRequestedWorkspace(targetDateStr), isNull);

      // Date must now be in booked_dates
      final booked = await storage.getBookedDates();
      expect(booked.contains(targetDateStr), isTrue);
    });
  });
}
