import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // SECTION 1: Extreme Occupant Names & String Boundary Adversarial Suite
  // ═════════════════════════════════════════════════════════════════════════════
  group('1. Extreme Occupant Names & String Formatting Adversarial Tests', () {
    test('Single-word names (mononyms like "Cher", "Madonna", "Zendaya") do NOT throw StringIndexOutOfBoundsException', () {
      const mononyms = [
        'Cher',
        'Madonna',
        'Zendaya',
        'Prince',
        'Voltaire',
        'Plato',
        'Pelé',
        'Aristote',
        'A', // single character uppercase
        'z', // single character lowercase
      ];

      for (final name in mononyms) {
        final occupant = DeskOccupant(workspaceId: 'ws-test', occupantName: name);
        // Must never throw StringIndexOutOfBoundsException or RangeError
        expect(() => occupant.formattedDisplayName, returnsNormally,
            reason: 'formattedDisplayName threw on mononym: "$name"');
        final formatted = occupant.formattedDisplayName;
        expect(formatted, equals(name.toUpperCase()),
            reason: 'Expected single-word mononym "$name" to format as "${name.toUpperCase()}", got "$formatted"');
        expect(formatted, isNotEmpty);
      }
    });

    test('Multi-part names produce clean uppercase "LASTNAME F." format', () {
      final multiPartCases = <String, String>{
        'Jean-Baptiste De La Tour': 'TOUR J.',
        'Charles Louis de Montesquieu': 'MONTESQUIEU C.',
        'Ludwig van Beethoven': 'BEETHOVEN L.',
        'Gabriel José de la Concordia García Márquez': 'MÁRQUEZ G.',
        'Élodie François': 'FRANÇOIS É.',
        'Anne-Sophie De La Motte-Picquet': 'MOTTE-PICQUET A.',
        'Jean Dupont': 'DUPONT J.',
        'Marie Curie': 'CURIE M.',
        'Vincent Willem van Gogh': 'GOGH V.',
        'Pablo Diego José Francisco de Paula Juan Nepomuceno Crispín': 'CRISPÍN P.',
      };

      multiPartCases.forEach((input, expected) {
        final occupant = DeskOccupant(workspaceId: 'ws-test', occupantName: input);
        expect(() => occupant.formattedDisplayName, returnsNormally,
            reason: 'formattedDisplayName threw on multi-part name: "$input"');
        final formatted = occupant.formattedDisplayName;
        expect(formatted, equals(expected),
            reason: 'Failed for input: "$input". Expected "$expected", got "$formatted"');
      });
    });

    test('Empty, pure whitespace, tab, and newline names provide safe fallback without throwing', () {
      const blankCases = [
        '',
        ' ',
        '   ',
        '\t',
        '\n',
        '\r\n',
        '  \t  \n  ',
      ];

      for (final blank in blankCases) {
        final occupant = DeskOccupant(workspaceId: 'ws-test', occupantName: blank);
        expect(() => occupant.formattedDisplayName, returnsNormally,
            reason: 'formattedDisplayName threw on whitespace input: "$blank"');
        expect(occupant.formattedDisplayName, equals(''));

        expect(() => occupant.initials, returnsNormally);
        expect(occupant.initials, equals('?'));

        expect(() => occupant.shortName, returnsNormally);
        expect(occupant.shortName, equals('?'));
      }
    });

    test('Hyphenated single words vs hyphenated multi words formatting robustness', () {
      // Single hyphenated word: no spaces -> mononym behavior
      final singleHyphen = const DeskOccupant(workspaceId: 'ws-1', occupantName: 'Jean-Luc');
      expect(singleHyphen.formattedDisplayName, equals('JEAN-LUC'));

      // Hyphenated first name + last name
      final hyphenFirst = const DeskOccupant(workspaceId: 'ws-2', occupantName: 'Jean-Luc Godard');
      expect(hyphenFirst.formattedDisplayName, equals('GODARD J.'));

      // First name + hyphenated last name
      final hyphenLast = const DeskOccupant(workspaceId: 'ws-3', occupantName: 'Claire Chazal-Poivre');
      expect(hyphenLast.formattedDisplayName, equals('CHAZAL-POIVRE C.'));
    });

    test('Punctuation, numbers, emojis, and irregular characters in occupant name', () {
      final occNumber = const DeskOccupant(workspaceId: 'ws-num', occupantName: 'Occupant 007');
      expect(occNumber.formattedDisplayName, equals('007 O.'));

      final occEmoji = const DeskOccupant(workspaceId: 'ws-emo', occupantName: '🤖 Super Bot');
      expect(() => occEmoji.formattedDisplayName, returnsNormally);
      expect(occEmoji.formattedDisplayName, isNotEmpty);

      final occSpecial = const DeskOccupant(workspaceId: 'ws-spec', occupantName: '---');
      expect(() => occSpecial.formattedDisplayName, returnsNormally);
      expect(occSpecial.formattedDisplayName, equals('---'));
    });

    test('DeskOccupant.fromJson resilience against null and empty occupant name representations', () {
      final jsonNullName = DeskOccupant.fromJson({'workspaceId': 'ws-1', 'occupantName': null});
      expect(jsonNullName.occupantName, equals('Occupant'));
      expect(jsonNullName.formattedDisplayName, equals('OCCUPANT'));

      final jsonEmptyMap = DeskOccupant.fromJson({});
      expect(jsonEmptyMap.occupantName, equals('Occupant'));
      expect(jsonEmptyMap.formattedDisplayName, equals('OCCUPANT'));
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // SECTION 2: Room Filter Sorting Algorithm & Chip Exclusion Adversarial Suite
  // ═════════════════════════════════════════════════════════════════════════════
  group('2. Room Filter Sorting Algorithm & Exclusion Adversarial Tests', () {
    // Exact specification of room summary sorting comparator
    int compareRoomSummaries({
      required int aFavs,
      required int aTotal,
      required String aName,
      required int bFavs,
      required int bTotal,
      required String bName,
    }) {
      // 1. Favorite count descending
      final favComp = bFavs.compareTo(aFavs);
      if (favComp != 0) return favComp;
      // 2. Total occupants descending
      final occComp = bTotal.compareTo(aTotal);
      if (occComp != 0) return occComp;
      // 3. Alphabetical ascending
      return aName.toLowerCase().compareTo(bName.toLowerCase());
    }

    test('10 rooms with varied favorite counts and total occupants: verified exact 3-tier sort order', () {
      // Define 10 rooms designed to rigorously stress every comparator branch:
      // Room 1: 3 favs, 4 total
      // Room 2: 2 favs, 6 total
      // Room 3: 2 favs, 3 total
      // Room 4: 1 fav, 5 total, name "Alpha Room"
      // Room 5: 1 fav, 5 total, name "Zeta Room" (tests tie-breaker alphabetical)
      // Room 6: 1 fav, 2 total, name "Beta Room"
      // Room 7: 0 fav, 8 total, name "Omega Room"
      // Room 8: 0 fav, 4 total, name "Blue Room"
      // Room 9: 0 fav, 4 total, name "Yellow Room" (tests tie-breaker alphabetical for 0 favs)
      // Room 10: 0 fav, 1 total, name "Solo Room"

      final rooms = [
        {'name': 'Yellow Room', 'favs': 0, 'total': 4},
        {'name': 'Room_MidFav_Sparse', 'favs': 2, 'total': 3},
        {'name': 'Zeta Room', 'favs': 1, 'total': 5},
        {'name': 'Room_HighFav', 'favs': 3, 'total': 4},
        {'name': 'Solo Room', 'favs': 0, 'total': 1},
        {'name': 'Beta Room', 'favs': 1, 'total': 2},
        {'name': 'Omega Room', 'favs': 0, 'total': 8},
        {'name': 'Blue Room', 'favs': 0, 'total': 4},
        {'name': 'Room_MidFav_Dense', 'favs': 2, 'total': 6},
        {'name': 'Alpha Room', 'favs': 1, 'total': 5},
      ];

      rooms.sort((a, b) => compareRoomSummaries(
            aFavs: a['favs'] as int,
            aTotal: a['total'] as int,
            aName: a['name'] as String,
            bFavs: b['favs'] as int,
            bTotal: b['total'] as int,
            bName: b['name'] as String,
          ));

      final sortedNames = rooms.map((r) => r['name'] as String).toList();

      final expectedOrder = [
        'Room_HighFav',        // Favs: 3, Occ: 4
        'Room_MidFav_Dense',   // Favs: 2, Occ: 6
        'Room_MidFav_Sparse',  // Favs: 2, Occ: 3
        'Alpha Room',          // Favs: 1, Occ: 5 (Alpha < Zeta)
        'Zeta Room',           // Favs: 1, Occ: 5
        'Beta Room',           // Favs: 1, Occ: 2
        'Omega Room',          // Favs: 0, Occ: 8
        'Blue Room',           // Favs: 0, Occ: 4 (Blue < Yellow)
        'Yellow Room',         // Favs: 0, Occ: 4
        'Solo Room',           // Favs: 0, Occ: 1
      ];

      expect(sortedNames, equals(expectedOrder));
    });

    testWidgets('Full TeamMapScreen integration: 10 rooms sorted properly and 0-occupant rooms strictly excluded', (tester) async {
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'site_id': 'site-stress',
        'floor_id': 'floor-stress',
        'refresh_token': 'stress-token',
        'favorite_colleagues': jsonEncode([
          {'id': 'fav-user-1', 'name': 'Alice Favorite', 'email': 'alice@corp.com'},
          {'id': 'fav-user-2', 'name': 'Bob Favorite', 'email': 'bob@corp.com'},
          {'id': 'fav-user-3', 'name': 'Charlie Favorite', 'email': 'charlie@corp.com'},
        ]),
      });

      // Build mock workspaces for:
      // 10 occupied rooms + 2 empty meeting rooms
      final mockAllWorkspaces = <Map<String, dynamic>>[];
      final mockOccupantsData = <Map<String, dynamic>>[];

      // Helper to populate room workspaces & occupants
      void populateRoom({
        required String roomPrefix,
        required int favCount,
        required int regularCount,
      }) {
        final totalDesks = favCount + regularCount;
        for (int i = 1; i <= totalDesks; i++) {
          final wsId = '$roomPrefix-0$i';
          mockAllWorkspaces.add({
            'id': wsId,
            'name': wsId,
            'roomName': roomPrefix,
            'workspaceType': 'Desk',
            'isReservable': true,
          });

          final isFav = i <= favCount;
          mockOccupantsData.add({
            'workspaceId': wsId,
            'status': 'Reserved',
            'bookedTimeSlot': {
              'user': {
                'id': isFav ? 'fav-user-$i' : 'reg-user-$roomPrefix-$i',
                'name': isFav ? 'Fav User $i' : 'Regular Person $i',
                'email': isFav ? 'fav$i@corp.com' : 'reg$i@corp.com',
              }
            }
          });
        }
      }

      // 1. Room_HighFav: 3 favs, 1 regular = 4 total
      populateRoom(roomPrefix: 'Room_HighFav', favCount: 3, regularCount: 1);
      // 2. Room_MidFav_Dense: 2 favs, 4 regular = 6 total
      populateRoom(roomPrefix: 'Room_MidFav_Dense', favCount: 2, regularCount: 4);
      // 3. Room_MidFav_Sparse: 2 favs, 1 regular = 3 total
      populateRoom(roomPrefix: 'Room_MidFav_Sparse', favCount: 2, regularCount: 1);
      // 4. Alpha Room: 1 fav, 4 regular = 5 total
      populateRoom(roomPrefix: 'Alpha_Room', favCount: 1, regularCount: 4);
      // 5. Zeta Room: 1 fav, 4 regular = 5 total
      populateRoom(roomPrefix: 'Zeta_Room', favCount: 1, regularCount: 4);
      // 6. Beta Room: 1 fav, 1 regular = 2 total
      populateRoom(roomPrefix: 'Beta_Room', favCount: 1, regularCount: 1);
      // 7. Omega Room: 0 favs, 8 regular = 8 total
      populateRoom(roomPrefix: 'Omega_Room', favCount: 0, regularCount: 8);
      // 8. Blue Room: 0 favs, 4 regular = 4 total
      populateRoom(roomPrefix: 'Blue_Room', favCount: 0, regularCount: 4);
      // 9. Yellow Room: 0 favs, 4 regular = 4 total
      populateRoom(roomPrefix: 'Yellow_Room', favCount: 0, regularCount: 4);
      // 10. Solo Room: 0 favs, 1 regular = 1 total
      populateRoom(roomPrefix: 'Solo_Room', favCount: 0, regularCount: 1);

      // 11 & 12: Empty Meeting Rooms (0 occupants!)
      mockAllWorkspaces.add({
        'id': 'EmptyMeeting_A-01',
        'name': 'EmptyMeeting_A-01',
        'roomName': 'EmptyMeeting_A',
        'workspaceType': 'MeetingRoom',
        'isReservable': false,
      });
      mockAllWorkspaces.add({
        'id': 'EmptyMeeting_B-01',
        'name': 'EmptyMeeting_B-01',
        'roomName': 'EmptyMeeting_B',
        'workspaceType': 'MeetingRoom',
        'isReservable': false,
      });

      // Construct Mock Features for floor plan
      final mockFeatures = mockAllWorkspaces.map((ws) {
        return {
          'type': 'Feature',
          'properties': {
            'workspaceId': ws['id'],
            'name': ws['name'],
            'workspaceType': ws['workspaceType'],
          },
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [10.0, 10.0],
                [50.0, 10.0],
                [50.0, 40.0],
                [10.0, 40.0],
                [10.0, 10.0],
              ]
            ]
          }
        };
      }).toList();

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'atk-1', 'refresh_token': 'rtk-1'}), 200);
        }
        if (path.contains('/floors') && path.contains('/data')) {
          return http.Response(jsonEncode({'features': mockFeatures}), 200);
        }
        if (path.contains('/workspaces/all')) {
          return http.Response(jsonEncode(mockAllWorkspaces), 200);
        }
        if (path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': mockOccupantsData}), 200);
        }
        if (path.contains('/sites')) {
          return http.Response(jsonEncode([{'id': 'site-stress', 'name': 'Stress Site'}]), 200);
        }
        if (path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'floor-stress', 'name': 'Stress Floor'}]), 200);
        }
        return http.Response('[]', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // ── VERIFY CHIP EXCLUSIONS: Empty rooms MUST NOT appear in filter chips ──
      expect(
        find.descendant(
          of: find.byType(FilterChip),
          matching: find.textContaining('EmptyMeeting_A'),
        ),
        findsNothing,
        reason: 'EmptyMeeting_A has 0 occupants and must be strictly excluded from filter chips',
      );
      expect(
        find.descendant(
          of: find.byType(FilterChip),
          matching: find.textContaining('EmptyMeeting_B'),
        ),
        findsNothing,
        reason: 'EmptyMeeting_B has 0 occupants and must be strictly excluded from filter chips',
      );

      // ── VERIFY EXACT CHIP LABELS & SEQUENCE IN LISTVIEW ───────────────────
      // Find all FilterChips rendered in the horizontal bar
      final chipWidgets = tester.widgetList<FilterChip>(find.byType(FilterChip)).toList();
      // The first chip is "Tous les bureaux (...)"
      expect(chipWidgets.isNotEmpty, isTrue);

      final chipLabels = chipWidgets.map((chip) {
        final textWidget = chip.label as Text;
        return textWidget.data ?? '';
      }).toList();

      // Expected sorted chip labels:
      // Rooms with favorites show "${roomName} (${favoriteOccupants.length})"
      // Rooms with 0 favorites show "${roomName} (${totalOccupants})"
      final expectedLabels = [
        'Tous les bureaux (42)',
        'Room_HighFav (3)',       // 3 favs
        'Room_MidFav_Dense (2)',  // 2 favs, 6 total
        'Room_MidFav_Sparse (2)', // 2 favs, 3 total
        'Alpha_Room (1)',         // 1 fav, 5 total (Alpha < Zeta)
        'Zeta_Room (1)',          // 1 fav, 5 total
        'Beta_Room (1)',          // 1 fav, 2 total
        'Omega_Room (8)',         // 0 fav, 8 total
        'Blue_Room (4)',          // 0 fav, 4 total (Blue < Yellow)
        'Yellow_Room (4)',        // 0 fav, 4 total
        'Solo_Room (1)',          // 0 fav, 1 total
      ];

      expect(chipLabels, equals(expectedLabels),
          reason: 'Filter chips did not follow strict 3-tier sort criteria (favorites desc, total desc, alpha asc)');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // SECTION 3: WorkspaceMapViewer Layout Sizing & Stress (1 Desk vs 100 Desks)
  // ═════════════════════════════════════════════════════════════════════════════
  group('3. WorkspaceMapViewer Layout Sizing & Stress Adversarial Tests', () {
    testWidgets('Test 1 desk layout: renders cleanly without RenderFlex overflow or negative dimensions', (tester) async {
      final singleFeature = [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'single-desk-1', 'workspaceType': 'Desk', 'name': 'DS-01'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [10.0, 10.0],
                [50.0, 10.0],
                [50.0, 40.0],
                [10.0, 40.0],
                [10.0, 10.0],
              ]
            ]
          }
        }
      ];

      final singleWorkspace = [
        {'id': 'single-desk-1', 'name': 'DS-01', 'isBookable': true}
      ];

      final singleOccupant = {
        'single-desk-1': const DeskOccupant(
          workspaceId: 'single-desk-1',
          occupantName: 'Jean Dupont',
          occupantId: 'user-single',
        )
      };

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: singleFeature,
            workspaces: singleWorkspace,
            occupants: singleOccupant,
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Zero exceptions / overflows
      expect(tester.takeException(), isNull);

      // Verify occupant name rendered inside desk box
      expect(find.text('DUPONT J.'), findsOneWidget);

      // Verify canvas size is strictly positive
      final interactiveViewer = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      expect(interactiveViewer, isNotNull);

      final sizedBoxes = tester.widgetList<SizedBox>(find.byType(SizedBox));
      final canvasBox = sizedBoxes.firstWhere(
        (box) => (box.width != null && box.width! > 100) && (box.height != null && box.height! > 50),
      );
      expect(canvasBox.width!, greaterThan(0));
      expect(canvasBox.height!, greaterThan(0));
    });

    testWidgets('Test 100 desks layout stress: zero RenderFlex overflows and strict positive dimensions across viewports', (tester) async {
      // Build 100 desks arranged across a 10x10 geometric grid
      final features100 = <Map<String, dynamic>>[];
      final workspaces100 = <Map<String, dynamic>>[];
      final occupants100 = <String, DeskOccupant>{};
      final favIds = <String>{};

      int deskIndex = 0;
      for (int row = 0; row < 10; row++) {
        for (int col = 0; col < 10; col++) {
          deskIndex++;
          final wsId = 'desk-$deskIndex';
          final roomNumber = (row + 1).toString().padLeft(2, '0');
          final deskNumber = (col + 1).toString().padLeft(2, '0');
          final deskName = 'ROOM$roomNumber-$deskNumber';

          final x = col * 80.0 + 20.0;
          final y = row * 60.0 + 20.0;
          const w = 45.0;
          const h = 32.0;

          features100.add({
            'type': 'Feature',
            'properties': {
              'workspaceId': wsId,
              'name': deskName,
              'workspaceType': 'Desk',
            },
            'geometry': {
              'type': 'Polygon',
              'coordinates': [
                [
                  [x, y],
                  [x + w, y],
                  [x + w, y + h],
                  [x, y + h],
                  [x, y],
                ]
              ]
            }
          });

          workspaces100.add({
            'id': wsId,
            'name': deskName,
            'isBookable': true,
          });

          // Mix different occupant name patterns:
          // - mononyms ("Cher", "Madonna")
          // - multi-part names ("Jean-Baptiste De La Tour")
          // - empty/whitespace names
          // - favorites
          if (deskIndex % 3 == 0) {
            final isFav = deskIndex % 6 == 0;
            if (isFav) favIds.add('user-$deskIndex');

            String name;
            if (deskIndex % 15 == 0) {
              name = 'Cher';
            } else if (deskIndex % 12 == 0) {
              name = 'Jean-Baptiste De La Tour';
            } else if (deskIndex % 9 == 0) {
              name = '   ';
            } else {
              name = 'Colleague Number $deskIndex';
            }

            occupants100[wsId] = DeskOccupant(
              workspaceId: wsId,
              occupantName: name,
              occupantId: 'user-$deskIndex',
            );
          }
        }
      }

      // Test multiple aggressive viewport constraint dimensions
      final testViewports = [
        const Size(390, 844),   // Standard smartphone (iPhone 14)
        const Size(320, 480),   // Extreme compact screen (legacy small phone)
        const Size(1024, 1366), // Large iPad / Tablet screen
      ];

      for (final viewport in testViewports) {
        tester.view.physicalSize = viewport;
        tester.view.devicePixelRatio = 1.0;

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: WorkspaceMapViewer(
              features: features100,
              workspaces: workspaces100,
              occupants: occupants100,
              favoriteIds: favIds,
              onSelected: (_) {},
            ),
          ),
        ));
        await tester.pumpAndSettle();

        // 1. Zero RenderFlex or layout overflows
        expect(tester.takeException(), isNull,
            reason: 'RenderFlex overflow or layout exception detected on viewport: $viewport');

        // 2. All 100 desk positions exist in tree
        final deskFinders = find.byType(GestureDetector);
        expect(deskFinders.evaluate().length, greaterThanOrEqualTo(100),
            reason: 'Expected at least 100 desks positioned on map');

        // 3. Zoom buttons are accessible and functional without crash
        final zoomInFinder = find.byIcon(Icons.add);
        final zoomOutFinder = find.byIcon(Icons.remove);
        expect(zoomInFinder, findsOneWidget);
        expect(zoomOutFinder, findsOneWidget);

        await tester.tap(zoomInFinder);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);

        await tester.tap(zoomOutFinder);
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
      }

      tester.view.resetPhysicalSize();
    });

    testWidgets('WorkspaceMapViewer handles empty features and extreme coordinates gracefully', (tester) async {
      // Empty features
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: const [],
            workspaces: const [],
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Aucun plan disponible'), findsOneWidget);
      expect(tester.takeException(), isNull);

      // Negative coordinates normalized properly
      final negativeCoordsFeatures = [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'neg-1', 'workspaceType': 'Desk', 'name': 'NEG-01'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [
                [-200.0, -100.0],
                [-150.0, -100.0],
                [-150.0, -60.0],
                [-200.0, -60.0],
                [-200.0, -100.0],
              ]
            ]
          }
        }
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: negativeCoordsFeatures,
            workspaces: [{'id': 'neg-1', 'name': 'NEG-01'}],
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('01'), findsOneWidget);
      expect(find.text('NEG'), findsOneWidget);
    });
  });
}
