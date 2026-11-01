import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StorageService storage;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    storage = StorageService();
  });

  group('Offline Cache Persistence - StorageService (R3.1, R3.2, R3.3, R3.4)', () {
    // ── R3.1 & R3.3: Personal Elsewhere Bookings Map ──────────────────────────
    group('saveBookedElsewhereMap / getBookedElsewhereMap', () {
      test('returns empty map when nothing has been stored and no legacy dates exist', () async {
        final result = await storage.getBookedElsewhereMap();
        expect(result, isEmpty);
      });

      test('persists and retrieves elsewhere bookings map with exact date-to-workspace mapping', () async {
        final map = {
          '2026-11-01': 'Batiment A - Bureau 12',
          '2026-11-02': 'Site Nord - Desk 4B',
          '2026-11-05': 'Tour Mirabeau - Salle 3',
        };

        await storage.saveBookedElsewhereMap(map);
        final loaded = await storage.getBookedElsewhereMap();

        expect(loaded, equals(map));
        expect(loaded['2026-11-01'], 'Batiment A - Bureau 12');
        expect(loaded['2026-11-02'], 'Site Nord - Desk 4B');
        expect(loaded['2026-11-05'], 'Tour Mirabeau - Salle 3');
      });

      test('updates legacy booked_elsewhere_dates list for backwards compatibility', () async {
        final map = {
          '2026-11-10': 'Desk 1',
          '2026-11-11': 'Desk 2',
        };

        await storage.saveBookedElsewhereMap(map);
        final legacyList = await storage.getBookedElsewhereDates();

        expect(legacyList, containsAll(['2026-11-10', '2026-11-11']));
      });

      test('falls back gracefully to legacy booked_elsewhere_dates when map key is missing', () async {
        SharedPreferences.setMockInitialValues({
          'booked_elsewhere_dates': ['2026-11-01', '2026-11-02'],
        });

        final loaded = await storage.getBookedElsewhereMap();
        expect(loaded.keys, containsAll(['2026-11-01', '2026-11-02']));
        expect(loaded['2026-11-01'], 'Ailleurs');
      });

      test('handles corrupted JSON in booked_elsewhere_map gracefully without throwing', () async {
        SharedPreferences.setMockInitialValues({
          'booked_elsewhere_map': '{"corrupted_json: [invalid',
          'booked_elsewhere_dates': ['2026-11-03'],
        });

        final loaded = await storage.getBookedElsewhereMap();
        // Fallback or empty, should not crash
        expect(loaded.containsKey('2026-11-03'), isTrue);
      });

      test('overwrites previous elsewhere map cleanly', () async {
        await storage.saveBookedElsewhereMap({'2026-11-01': 'Old Desk'});
        await storage.saveBookedElsewhereMap({'2026-11-02': 'New Desk'});

        final loaded = await storage.getBookedElsewhereMap();
        expect(loaded.containsKey('2026-11-01'), isFalse);
        expect(loaded['2026-11-02'], 'New Desk');
      });
    });

    // ── R3.3: Occupied by Others Map ──────────────────────────────────────────
    group('saveOccupiedByOthers / getOccupiedByOthers', () {
      test('returns empty map when no occupancy data has been saved', () async {
        final result = await storage.getOccupiedByOthers();
        expect(result, isEmpty);
      });

      test('persists and retrieves occupied by others map accurately', () async {
        final map = {
          '2026-11-01': 'DUPONT Jean',
          '2026-11-02': 'MARTIN Sophie',
          '2026-11-03': 'BERNARD Luc',
        };

        await storage.saveOccupiedByOthers(map);
        final loaded = await storage.getOccupiedByOthers();

        expect(loaded, equals(map));
        expect(loaded['2026-11-01'], 'DUPONT Jean');
        expect(loaded['2026-11-02'], 'MARTIN Sophie');
      });

      test('handles corrupted JSON in occupied_by_others_map gracefully', () async {
        SharedPreferences.setMockInitialValues({
          'occupied_by_others_map': '{{{not valid json}}',
        });

        final loaded = await storage.getOccupiedByOthers();
        expect(loaded, isEmpty);
      });

      test('allows saving empty map to clear or reset occupancy', () async {
        await storage.saveOccupiedByOthers({'2026-11-01': 'DUPONT Jean'});
        await storage.saveOccupiedByOthers({});

        final loaded = await storage.getOccupiedByOthers();
        expect(loaded, isEmpty);
      });
    });

    // ── R3.2: Delegated Bookings Map ──────────────────────────────────────────
    group('saveDelegatedBookingsMap / getDelegatedBookingsMap', () {
      test('returns empty map when no delegated bookings have been saved', () async {
        final result = await storage.getDelegatedBookingsMap();
        expect(result, isEmpty);
      });

      test('persists and retrieves delegated bookings map accurately', () async {
        final map = {
          '2026-11-04': 'Alice Dupont (Desk B12)',
          '2026-11-05': 'Bob Martin (Desk A01)',
        };

        await storage.saveDelegatedBookingsMap(map);
        final loaded = await storage.getDelegatedBookingsMap();

        expect(loaded, equals(map));
        expect(loaded['2026-11-04'], 'Alice Dupont (Desk B12)');
      });

      test('handles corrupted JSON in delegated_bookings_map gracefully', () async {
        SharedPreferences.setMockInitialValues({
          'delegated_bookings_map': '{"incomplete":',
        });

        final loaded = await storage.getDelegatedBookingsMap();
        expect(loaded, isEmpty);
      });
    });

    // ── R3.4: Floor Occupants Persistence with DeskOccupant ────────────────────
    group('saveFloorOccupants / getFloorOccupants', () {
      test('returns empty map when no occupants exist for given floor and date', () async {
        final result = await storage.getFloorOccupants('floor_1', '2026-11-01');
        expect(result, isEmpty);
      });

      test('persists and deserializes comprehensive DeskOccupant map with full metadata', () async {
        const occupant1 = DeskOccupant(
          workspaceId: 'ws_001',
          occupantName: 'Jean Dupont',
          occupantId: 'user_123',
          occupantEmail: 'jean.dupont@company.com',
          isMe: true,
          isDelegated: false,
          isDelegatedByMe: false,
          isDelegatedForMe: false,
          isDelegatedOther: false,
        );

        const occupant2 = DeskOccupant(
          workspaceId: 'ws_002',
          occupantName: 'Sophie Martin',
          occupantId: 'user_456',
          occupantEmail: 'sophie.martin@company.com',
          isMe: false,
          isDelegated: true,
          isDelegatedByMe: true,
          isDelegatedForMe: false,
          isDelegatedOther: false,
          bookedByName: 'Jean Dupont',
        );

        const occupant3 = DeskOccupant(
          workspaceId: 'ws_003',
          occupantName: 'Alexandre Roux',
          occupantId: 'user_789',
          occupantEmail: 'alex.roux@company.com',
          isMe: false,
          isDelegated: true,
          isDelegatedByMe: false,
          isDelegatedForMe: true,
          isDelegatedOther: false,
          bookedByName: 'Directeur',
        );

        final occupantsMap = {
          'ws_001': occupant1,
          'ws_002': occupant2,
          'ws_003': occupant3,
        };

        await storage.saveFloorOccupants('floor_east_3', '2026-11-15', occupantsMap);
        final loaded = await storage.getFloorOccupants('floor_east_3', '2026-11-15');

        expect(loaded.length, 3);

        final o1 = loaded['ws_001']!;
        expect(o1.workspaceId, 'ws_001');
        expect(o1.occupantName, 'Jean Dupont');
        expect(o1.occupantId, 'user_123');
        expect(o1.occupantEmail, 'jean.dupont@company.com');
        expect(o1.isMe, isTrue);
        expect(o1.isDelegated, isFalse);

        final o2 = loaded['ws_002']!;
        expect(o2.workspaceId, 'ws_002');
        expect(o2.occupantName, 'Sophie Martin');
        expect(o2.isMe, isFalse);
        expect(o2.isDelegated, isTrue);
        expect(o2.isDelegatedByMe, isTrue);
        expect(o2.bookedByName, 'Jean Dupont');

        final o3 = loaded['ws_003']!;
        expect(o3.workspaceId, 'ws_003');
        expect(o3.occupantName, 'Alexandre Roux');
        expect(o3.isDelegatedForMe, isTrue);
        expect(o3.bookedByName, 'Directeur');
      });

      test('strictly isolates occupants storage across distinct floors and distinct dates', () async {
        const occupantFloor1 = DeskOccupant(
          workspaceId: 'ws_001',
          occupantName: 'Floor 1 Occupant',
        );
        const occupantFloor2 = DeskOccupant(
          workspaceId: 'ws_002',
          occupantName: 'Floor 2 Occupant',
        );
        const occupantDate2 = DeskOccupant(
          workspaceId: 'ws_001',
          occupantName: 'Tomorrow Occupant',
        );

        await storage.saveFloorOccupants('floor_1', '2026-11-01', {'ws_001': occupantFloor1});
        await storage.saveFloorOccupants('floor_2', '2026-11-01', {'ws_002': occupantFloor2});
        await storage.saveFloorOccupants('floor_1', '2026-11-02', {'ws_001': occupantDate2});

        final f1d1 = await storage.getFloorOccupants('floor_1', '2026-11-01');
        final f2d1 = await storage.getFloorOccupants('floor_2', '2026-11-01');
        final f1d2 = await storage.getFloorOccupants('floor_1', '2026-11-02');
        final nonExistent = await storage.getFloorOccupants('floor_3', '2026-11-01');

        expect(f1d1['ws_001']?.occupantName, 'Floor 1 Occupant');
        expect(f1d1.containsKey('ws_002'), isFalse);

        expect(f2d1['ws_002']?.occupantName, 'Floor 2 Occupant');
        expect(f2d1.containsKey('ws_001'), isFalse);

        expect(f1d2['ws_001']?.occupantName, 'Tomorrow Occupant');
        expect(nonExistent, isEmpty);
      });

      test('handles corrupted JSON in floor_occupants string gracefully', () async {
        SharedPreferences.setMockInitialValues({
          'floor_occupants_f1_2026-11-01': '{"ws1": "not a valid desk occupant map"}',
        });

        final loaded = await storage.getFloorOccupants('f1', '2026-11-01');
        expect(loaded, isA<Map<String, DeskOccupant>>());
      });
    });

    // ── R3.4: Floor Plan & Floor Workspaces Persistence ───────────────────────
    group('saveFloorPlanData / getFloorPlanData', () {
      test('returns null when floor plan is not cached', () async {
        final result = await storage.getFloorPlanData('unknown_floor');
        expect(result, isNull);
      });

      test('persists and retrieves complex GeoJSON plan structure', () async {
        final planData = {
          'type': 'FeatureCollection',
          'features': [
            {
              'type': 'Feature',
              'properties': {'workspaceId': 'ws-101', 'name': 'Bureau 101'},
              'geometry': {
                'type': 'Polygon',
                'coordinates': [
                  [[10.0, 10.0], [40.0, 10.0], [40.0, 40.0], [10.0, 40.0], [10.0, 10.0]]
                ]
              }
            }
          ]
        };

        await storage.saveFloorPlanData('floor_main', planData);
        final loaded = await storage.getFloorPlanData('floor_main');

        expect(loaded, isNotNull);
        expect(loaded['type'], 'FeatureCollection');
        expect(loaded['features'], hasLength(1));
        expect(loaded['features'][0]['properties']['workspaceId'], 'ws-101');
      });

      test('handles corrupted JSON in floor_plan data gracefully', () async {
        SharedPreferences.setMockInitialValues({
          'floor_plan_fl_err': '{{corrupted: geojson',
        });

        final loaded = await storage.getFloorPlanData('fl_err');
        expect(loaded, isNull);
      });
    });

    group('saveFloorWorkspaces / getFloorWorkspaces', () {
      test('returns empty list when workspaces are not cached', () async {
        final result = await storage.getFloorWorkspaces('unknown_floor');
        expect(result, isEmpty);
      });

      test('persists and retrieves list of workspace maps', () async {
        final workspaces = [
          {'id': 'ws_1', 'name': 'A-01', 'isBookable': true, 'siteId': 's1'},
          {'id': 'ws_2', 'name': 'A-02', 'isBookable': false, 'siteId': 's1'},
        ];

        await storage.saveFloorWorkspaces('fl_2', workspaces);
        final loaded = await storage.getFloorWorkspaces('fl_2');

        expect(loaded, hasLength(2));
        expect(loaded[0]['id'], 'ws_1');
        expect(loaded[0]['isBookable'], isTrue);
        expect(loaded[1]['id'], 'ws_2');
        expect(loaded[1]['isBookable'], isFalse);
      });

      test('handles corrupted JSON in floor_workspaces data gracefully', () async {
        SharedPreferences.setMockInitialValues({
          'floor_workspaces_fl_bad': '{"not_a_list": true}',
        });

        final loaded = await storage.getFloorWorkspaces('fl_bad');
        expect(loaded, isEmpty);
      });
    });
  });
}
