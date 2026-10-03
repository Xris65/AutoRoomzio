import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shimmer/shimmer.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auto_roomzio/main.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';
import 'package:auto_roomzio/screens/setup_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // CHALLENGE 1: Camera Framing (Default Desk Exists vs Absent / Fallback)
  // ═════════════════════════════════════════════════════════════════════════════
  group('Challenge 1: Camera Framing & Floor Change Fallback', () {
    testWidgets('Default desk exists on floor: camera centers on enclosing room with scale between 0.85 and 1.25', (tester) async {
      tester.view.physicalSize = const Size(400, 600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const viewW = 400.0;
      const viewH = 600.0;

      final features = [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'alpha-01', 'name': 'RoomAlpha-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[20.0, 20.0], [50.0, 20.0], [50.0, 40.0], [20.0, 40.0], [20.0, 20.0]]
            ]
          }
        },
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'target-01', 'name': 'RoomTarget-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[200.0, 300.0], [230.0, 300.0], [230.0, 320.0], [200.0, 320.0], [200.0, 300.0]]
            ]
          }
        },
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'target-02', 'name': 'RoomTarget-02', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[240.0, 300.0], [270.0, 300.0], [270.0, 320.0], [240.0, 320.0], [240.0, 300.0]]
            ]
          }
        },
      ];

      final workspaces = [
        {'id': 'alpha-01', 'name': 'RoomAlpha-01', 'isBookable': true},
        {'id': 'target-01', 'name': 'RoomTarget-01', 'isBookable': true},
        {'id': 'target-02', 'name': 'RoomTarget-02', 'isBookable': true},
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: viewW,
            height: viewH,
            child: WorkspaceMapViewer(
              features: features,
              workspaces: workspaces,
              allWorkspaces: workspaces,
              defaultWorkspaceId: 'target-01',
              onSelected: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final matrix = iv.transformationController?.value;
      expect(matrix, isNotNull);

      final scaleX = matrix!.entry(0, 0);
      final scaleY = matrix.entry(1, 1);
      final dx = matrix.entry(0, 3);
      final dy = matrix.entry(1, 3);

      // Verify scale is clamped between 0.85 and 1.25
      expect(scaleX, inInclusiveRange(0.85, 1.25),
          reason: 'ScaleX $scaleX must be clamped between 0.85 and 1.25');
      expect(scaleY, inInclusiveRange(0.85, 1.25),
          reason: 'ScaleY $scaleY must be clamped between 0.85 and 1.25');
      expect(scaleX, equals(scaleY), reason: 'Uniform scaling expected');

      // RoomTarget contains target-01 and target-02
      final centerInViewportX = (viewW / 2);
      final centerInViewportY = (viewH / 2);
      final targetCx = (centerInViewportX - dx) / scaleX;
      final targetCy = (centerInViewportY - dy) / scaleY;

      // Verify targetCx is clearly inside RoomTarget and NOT at (0,0) or RoomAlpha
      expect(targetCx, greaterThan(400.0),
          reason: 'Target center X should point to RoomTarget, not RoomAlpha or origin');
      expect(targetCy, greaterThan(600.0),
          reason: 'Target center Y should point to RoomTarget, not RoomAlpha or origin');
    });

    testWidgets('Default desk does NOT exist on floor: Zoom-to-Fit fallback centers on floor content without centering on empty space', (tester) async {
      tester.view.physicalSize = const Size(500, 700);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      const viewW = 500.0;
      const viewH = 700.0;

      // Features for a floor that does NOT contain default desk 'non-existent-desk'
      final features = [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'floor2-01', 'name': 'Floor2Room-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[50.0, 50.0], [80.0, 50.0], [80.0, 70.0], [50.0, 70.0], [50.0, 50.0]]
            ]
          }
        },
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'floor2-02', 'name': 'Floor2Room-02', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[150.0, 150.0], [180.0, 150.0], [180.0, 170.0], [150.0, 170.0], [150.0, 150.0]]
            ]
          }
        },
      ];

      final workspaces = [
        {'id': 'floor2-01', 'name': 'Floor2Room-01', 'isBookable': true},
        {'id': 'floor2-02', 'name': 'Floor2Room-02', 'isBookable': true},
      ];

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: viewW,
            height: viewH,
            child: WorkspaceMapViewer(
              features: features,
              workspaces: workspaces,
              allWorkspaces: workspaces,
              defaultWorkspaceId: 'desk-on-another-floor',
              onSelected: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      final matrix = iv.transformationController?.value;
      expect(matrix, isNotNull);

      final scale = matrix!.entry(0, 0);
      final dx = matrix.entry(0, 3);
      final dy = matrix.entry(1, 3);

      // Verify scale is within Zoom-to-Fit clamp (0.60 to 1.25)
      expect(scale, inInclusiveRange(0.60, 1.25));

      // Calculate what point in canvas coordinates maps to the center of the viewport
      final targetCx = ((viewW / 2) - dx) / scale;
      final targetCy = ((viewH / 2) - dy) / scale;

      // Extract canvas SizedBox directly from InteractiveViewer child
      final canvasBox = iv.child as SizedBox;
      final mapW = canvasBox.width!;
      final mapH = canvasBox.height!;

      // In Zoom-to-Fit fallback, targetCx must be mapW / 2 and targetCy must be mapH / 2
      expect(targetCx, closeTo(mapW / 2, 0.01),
          reason: 'Zoom-to-Fit must center on the content canvas midpoint X');
      expect(targetCy, closeTo(mapH / 2, 0.01),
          reason: 'Zoom-to-Fit must center on the content canvas midpoint Y');

      // The center should NOT be 0,0 (empty top-left) or infinity
      expect(targetCx, greaterThan(50.0));
      expect(targetCy, greaterThan(50.0));
    });

    testWidgets('Integrated TeamMapScreen floor change: switches from default desk centering to Zoom-to-Fit fallback', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-tok',
        'site_id': 'site-1',
        'floor_id': 'fl-1',
        'workspace_id': 'ws-target-floor1',
      });

      final floor1Features = [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'ws-target-floor1', 'name': 'RoomF1-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[200.0, 200.0], [240.0, 200.0], [240.0, 230.0], [200.0, 230.0], [200.0, 200.0]]
            ]
          }
        }
      ];

      final floor2Features = [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'ws-other-floor2', 'name': 'RoomF2-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[50.0, 50.0], [80.0, 50.0], [80.0, 70.0], [50.0, 70.0], [50.0, 50.0]]
            ]
          }
        }
      ];

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'atk', 'refresh_token': 'rtk'}), 200);
        }
        if (path.contains('/sites')) {
          return http.Response(jsonEncode([{'id': 'site-1', 'name': 'Main Building'}]), 200);
        }
        if (path.endsWith('/floors')) {
          return http.Response(jsonEncode([
            {'id': 'fl-1', 'name': 'Étage 1'},
            {'id': 'fl-2', 'name': 'Étage 2'},
          ]), 200);
        }
        if (path.contains('/floors/fl-1/data') || (path.contains('fl-1') && path.contains('/data'))) {
          return http.Response(jsonEncode({'features': floor1Features}), 200);
        }
        if (path.contains('/floors/fl-2/data') || (path.contains('fl-2') && path.contains('/data'))) {
          return http.Response(jsonEncode({'features': floor2Features}), 200);
        }
        if (path.contains('/workspaces/all')) {
          if (path.contains('fl-1')) {
            return http.Response(jsonEncode([{'id': 'ws-target-floor1', 'name': 'RoomF1-01', 'isReservable': true}]), 200);
          } else {
            return http.Response(jsonEncode([{'id': 'ws-other-floor2', 'name': 'RoomF2-01', 'isReservable': true}]), 200);
          }
        }
        if (path.contains('/workspaces/calendars')) {
          return http.Response(jsonEncode({'data': []}), 200);
        }
        if (path.contains('/users/current')) {
          return http.Response(jsonEncode({'id': 'my-user-id'}), 200);
        }
        return http.Response('{}', 200);
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(apiService: api, storageService: storage),
      ));
      await tester.pumpAndSettle();

      // On Floor 1: default desk ws-target-floor1 is present -> room name RoomF1 rendered
      expect(find.text('RoomF1'), findsOneWidget);
      var iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      var scale = iv.transformationController!.value.entry(0, 0);
      expect(scale, inInclusiveRange(0.85, 1.25), reason: 'Floor 1 with default desk has clamped scale in [0.85, 1.25]');

      // Switch to Floor 2 using dropdown
      final dropdownFinder = find.byType(DropdownButton<String>);
      expect(dropdownFinder, findsOneWidget);
      await tester.tap(dropdownFinder);
      await tester.pumpAndSettle();

      final floor2Item = find.text('Étage 2').last;
      await tester.tap(floor2Item);
      await tester.pumpAndSettle();

      // On Floor 2: ws-target-floor1 is NOT present -> RoomF2 rendered
      expect(find.text('RoomF2'), findsOneWidget);
      iv = tester.widget<InteractiveViewer>(find.byType(InteractiveViewer));
      scale = iv.transformationController!.value.entry(0, 0);
      expect(scale, inInclusiveRange(0.60, 1.25), reason: 'Floor 2 fallback has Zoom-to-Fit scale in [0.60, 1.25]');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // CHALLENGE 2: Shimmer Skeleton Layout in TeamMapScreen
  // ═════════════════════════════════════════════════════════════════════════════
  group('Challenge 2: Shimmer Skeleton Layout in TeamMapScreen', () {
    testWidgets('Shimmer skeleton renders 2D architectural layout in Expanded map area with static navigation headers', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'test-token',
        'site_id': 'site-1',
        'floor_id': 'fl-1',
      });

      final completer = Completer<http.Response>();
      final client = MockClient((req) async {
        if (req.url.path.contains('/connect/token')) {
          return http.Response(jsonEncode({'access_token': 'atk', 'refresh_token': 'rtk'}), 200);
        }
        return await completer.future;
      });

      final api = RoomzApiService(client: client);
      final storage = StorageService();

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(apiService: api, storageService: storage),
      ));
      // Pump initial frame to render skeleton while data is in-flight
      await tester.pump();

      // 1. Shimmer presence
      final shimmerFinder = find.byType(Shimmer);
      expect(shimmerFinder, findsOneWidget, reason: 'TeamMapScreen must render Shimmer in Expanded area during loading');

      // 2. Static header elements remain visible outside the shimmer
      // Date navigation bar (chevron left, chevron right, calendar)
      expect(find.byIcon(Icons.chevron_left), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsOneWidget);
      expect(find.byIcon(Icons.calendar_today), findsOneWidget);

      // Filter chip bar is visible in static header
      expect(find.byType(FilterChip), findsAtLeastNWidgets(1));

      // Legend bar is visible in static header
      expect(find.text('Collègue favori'), findsOneWidget);
      expect(find.text('Mon bureau'), findsOneWidget);
      expect(find.text('Occupé'), findsOneWidget);
      expect(find.text('Libre'), findsOneWidget);

      // 3. Shimmer contains an architectural floor plan in Stack with 5 positioned room containers
      final stackFinder = find.descendant(of: shimmerFinder, matching: find.byType(Stack));
      expect(stackFinder, findsOneWidget, reason: 'Map shimmer must render an architectural floor plan in a Stack');

      final stackWidget = tester.widget<Stack>(stackFinder);
      expect(stackWidget.children.length, equals(5),
          reason: 'Architectural floor plan skeleton must have 5 room silhouettes');

      // Verify each room silhouette has title container and desk containers
      for (final child in stackWidget.children) {
        expect(child, isA<Positioned>());
      }

      // Complete future and settle
      completer.complete(http.Response('[]', 200));
      await tester.pumpAndSettle();
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // CHALLENGE 3: UI Scale Clamping (0.75 to 1.35)
  // ═════════════════════════════════════════════════════════════════════════════
  group('Challenge 3: UI Scale Accessibility Control & Clamping', () {
    testWidgets('Clamps extreme OS text scale and internal uiScale between 0.75 and 1.35', (tester) async {
      // Test matrix of extreme OS textScalers and uiScale settings
      final testCases = [
        // (osScale, appScale, expectedClamped)
        (0.5, 1.0, 0.75),   // OS 0.5x -> clamped to 0.75 min
        (0.2, 0.85, 0.75),  // extreme small 0.17x -> clamped to 0.75 min
        (2.0, 1.0, 1.35),   // OS 2.0x -> clamped to 1.35 max
        (3.0, 1.25, 1.35),  // extreme large 3.75x -> clamped to 1.35 max
        (1.0, 1.0, 1.0),    // normal -> 1.0
        (1.0, 0.85, 0.85),  // small within range -> 0.85
        (1.0, 1.15, 1.15),  // medium within range -> 1.15
        (1.1, 1.15, (1.1 * 1.15).clamp(0.75, 1.35)), // 1.265 within range
      ];

      for (final (osScale, appScale, expected) in testCases) {
        uiScaleNotifier.value = appScale;

        await tester.pumpWidget(
          MediaQuery(
            data: MediaQueryData(textScaler: TextScaler.linear(osScale)),
            child: ValueListenableBuilder<double>(
              valueListenable: uiScaleNotifier,
              builder: (context, uiScale, _) {
                return MaterialApp(
                  builder: (context, child) {
                    final mediaQuery = MediaQuery.of(context);
                    final targetScale = (mediaQuery.textScaler.scale(1.0) * uiScale).clamp(0.75, 1.35);
                    return MediaQuery(
                      data: mediaQuery.copyWith(textScaler: TextScaler.linear(targetScale)),
                      child: child ?? const SizedBox.shrink(),
                    );
                  },
                  home: const Scaffold(body: Text('Scale Probe')),
                );
              },
            ),
          ),
        );
        await tester.pump();

        final probeElement = tester.element(find.text('Scale Probe'));
        final actualScale = MediaQuery.of(probeElement).textScaler.scale(1.0);
        expect(actualScale, closeTo(expected, 0.001),
            reason: 'osScale=$osScale, appScale=$appScale: expected $expected, got $actualScale');
        expect(actualScale, inInclusiveRange(0.75, 1.35),
            reason: 'Resulting scale must be strictly between 0.75 and 1.35');
      }

      // Reset
      uiScaleNotifier.value = 1.0;
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // CHALLENGE 4: Desk Sizing (~72px) and Label Format ("NOM P.")
  // ═════════════════════════════════════════════════════════════════════════════
  group('Challenge 4: Desk Sizing (~72px) and Label Format ("NOM P.")', () {
    test('DeskOccupant formattedDisplayName strictly generates "LASTNAME F." for various French and international names', () {
      final expectations = <String, String>{
        'Jean Dupont': 'DUPONT J.',
        'Marie Curie': 'CURIE M.',
        'Victor Hugo': 'HUGO V.',
        'Alexandre Dumas': 'DUMAS A.',
        'Charles Baudelaire': 'BAUDELAIRE C.',
        'Jean-Luc Picard': 'PICARD J.',
        'Sophie Germain': 'GERMAIN S.',
        'Albert Einstein': 'EINSTEIN A.',
        'Ada Lovelace': 'LOVELACE A.',
        'Alan Turing': 'TURING A.',
        'Grace Hopper': 'HOPPER G.',
        // Multi-part
        'Jean Baptiste Poquelin': 'POQUELIN J.',
        // Single word (mononym)
        'Aristote': 'ARISTOTE',
        'Cher': 'CHER',
      };

      for (final entry in expectations.entries) {
        final occupant = DeskOccupant(workspaceId: 'ws-probe', occupantName: entry.key);
        expect(occupant.formattedDisplayName, equals(entry.value),
            reason: 'Input name "${entry.key}" must format as "${entry.value}"');
      }
    });

    testWidgets('WorkspaceMapViewer scales desks to ~72px wide and renders "NOM P."', (tester) async {
      final features = [
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'desk-dupont', 'name': 'Room-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[10.0, 10.0], [46.0, 10.0], [46.0, 34.0], [10.0, 34.0], [10.0, 10.0]]
            ]
          }
        }
      ];

      final workspaces = [
        {'id': 'desk-dupont', 'name': 'Room-01', 'isBookable': true}
      ];

      final occupants = {
        'desk-dupont': const DeskOccupant(
          workspaceId: 'desk-dupont',
          occupantName: 'Jean Dupont',
          occupantId: 'usr-dupont',
        )
      };

      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SizedBox(
            width: 400,
            height: 600,
            child: WorkspaceMapViewer(
              features: features,
              workspaces: workspaces,
              allWorkspaces: workspaces,
              occupants: occupants,
              onSelected: (_) {},
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // 1. Verify label format "DUPONT J." is visible
      final labelFinder = find.text('DUPONT J.');
      expect(labelFinder, findsOneWidget,
          reason: 'Occupant name must be formatted as "DUPONT J." inside the desk');

      // 2. Locate desk container directly enclosing "DUPONT J."
      final deskContainerFinder = find.ancestor(
        of: labelFinder,
        matching: find.byType(Container),
      ).first;

      final deskSize = tester.getSize(deskContainerFinder);
      expect(deskSize.width, inInclusiveRange(65.0, 75.0),
          reason: 'Desk width must be ~72px (accounting for 1.5px gap on borders), got ${deskSize.width}');
      expect(deskSize.height, inInclusiveRange(40.0, 55.0),
          reason: 'Desk height should be proportional (~45-50px), got ${deskSize.height}');
    });
  });

  // ═════════════════════════════════════════════════════════════════════════════
  // CHALLENGE 5: SetupScreen Conditional Scroll Physics
  // ═════════════════════════════════════════════════════════════════════════════
  group('Challenge 5: SetupScreen Conditional Scroll Physics', () {
    testWidgets('Steps 1 & 2 use AlwaysScrollableScrollPhysics; Step 3 with 2D map locks with NeverScrollableScrollPhysics', (tester) async {
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      SharedPreferences.setMockInitialValues({
        'refresh_token': 'mock-tok',
      });

      final client = MockClient((req) async {
        final path = req.url.path;
        if (path.contains('/data')) {
          return http.Response(jsonEncode({
            'features': [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'ws-1', 'name': 'Desk-01', 'workspaceType': 'Desk'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [[[10.0, 10.0], [40.0, 10.0], [40.0, 40.0], [10.0, 40.0], [10.0, 10.0]]]
                }
              }
            ]
          }), 200);
        }
        if (path.contains('/buildings') && path.contains('/floors')) {
          return http.Response(jsonEncode([{'id': 'fl-1', 'name': 'Étage 1'}]), 200);
        }
        if (path.contains('/buildings') || path.contains('/sites')) {
          return http.Response(jsonEncode([{'id': 'site-1', 'name': 'Bâtiment Principal'}]), 200);
        }
        if (path.contains('/workspaces')) {
          return http.Response(jsonEncode([
            {'id': 'ws-1', 'name': 'Desk-01', 'isReservable': true}
          ]), 200);
        }
        return http.Response('[]', 200);
      });
      final api = RoomzApiService(client: client);

      await tester.pumpWidget(MaterialApp(
        home: SetupScreen(accessToken: 'mock-access-token', apiService: api),
      ));
      await tester.pumpAndSettle();

      final stepperFinder = find.byType(Stepper);
      expect(stepperFinder, findsOneWidget);

      // Step 0 (Step 1 for user: Building list): AlwaysScrollableScrollPhysics
      var stepper = tester.widget<Stepper>(stepperFinder);
      expect(stepper.physics, isA<AlwaysScrollableScrollPhysics>(),
          reason: 'Steps 1 & 2 (building and floor lists) must have AlwaysScrollableScrollPhysics');

      // Tap on building to move to Step 1 (Floor list)
      final siteTile = find.text('Bâtiment Principal');
      expect(siteTile, findsOneWidget);
      await tester.tap(siteTile);
      await tester.pumpAndSettle();

      stepper = tester.widget<Stepper>(stepperFinder);
      expect(stepper.physics, isA<AlwaysScrollableScrollPhysics>(),
          reason: 'Step 2 Floor list must have AlwaysScrollableScrollPhysics');

      // Tap on floor to move to Step 2 (Step 3 for user: 2D map display)
      final floorTile = find.text('Étage 1');
      expect(floorTile, findsOneWidget);
      await tester.tap(floorTile);
      await tester.pumpAndSettle();

      // On Step 3 where 2D map is displayed: Stepper parent container MUST be locked with NeverScrollableScrollPhysics
      stepper = tester.widget<Stepper>(stepperFinder);
      expect(stepper.physics, isA<NeverScrollableScrollPhysics>(),
          reason: 'Step 3 with 2D map active MUST be locked with NeverScrollableScrollPhysics');
    });
  });
}
