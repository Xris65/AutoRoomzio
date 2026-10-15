import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';

void main() {
  group('Évolution #4 : Coloration thermique des pièces (Room Heatmap)', () {
    // ── 1. Tests unitaires des calculs de ratios ──────────────────────────────
    test('calculateOccupancyRatio calculates bureaux_occupés / total_bureaux', () {
      expect(WorkspaceMapViewer.calculateOccupancyRatio(occupiedDesks: 0, totalDesks: 0), equals(0.0));
      expect(WorkspaceMapViewer.calculateOccupancyRatio(occupiedDesks: 0, totalDesks: 10), equals(0.0));
      expect(WorkspaceMapViewer.calculateOccupancyRatio(occupiedDesks: 2, totalDesks: 10), closeTo(0.20, 0.001));
      expect(WorkspaceMapViewer.calculateOccupancyRatio(occupiedDesks: 5, totalDesks: 10), closeTo(0.50, 0.001));
      expect(WorkspaceMapViewer.calculateOccupancyRatio(occupiedDesks: 8, totalDesks: 10), closeTo(0.80, 0.001));
      expect(WorkspaceMapViewer.calculateOccupancyRatio(occupiedDesks: 10, totalDesks: 10), equals(1.0));
      // Clamp edge case
      expect(WorkspaceMapViewer.calculateOccupancyRatio(occupiedDesks: 12, totalDesks: 10), equals(1.0));
    });

    test('calculateFreeRatio calculates places_libres / total_bureaux', () {
      expect(WorkspaceMapViewer.calculateFreeRatio(occupiedDesks: 0, totalDesks: 0), equals(1.0));
      expect(WorkspaceMapViewer.calculateFreeRatio(occupiedDesks: 0, totalDesks: 10), equals(1.0));
      expect(WorkspaceMapViewer.calculateFreeRatio(occupiedDesks: 2, totalDesks: 10), closeTo(0.80, 0.001));
      expect(WorkspaceMapViewer.calculateFreeRatio(occupiedDesks: 5, totalDesks: 10), closeTo(0.50, 0.001));
      expect(WorkspaceMapViewer.calculateFreeRatio(occupiedDesks: 8, totalDesks: 10), closeTo(0.20, 0.001));
      expect(WorkspaceMapViewer.calculateFreeRatio(occupiedDesks: 10, totalDesks: 10), equals(0.0));
    });

    // ── 2. Tests unitaires de la coloration thermique ─────────────────────────
    test('getRoomHeatmapColor returns appropriate pastel tint according to freeRatio thresholds', () {
      // 0 total desks -> transparent
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 0, totalDesks: 0),
        equals(Colors.transparent),
      );

      // 🟢 > 65% libre (ex: 2/10 occupés = 80% libre) -> Pastel Vert doux (0x1822C55E)
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 2, totalDesks: 10),
        equals(const Color(0x1822C55E)),
      );
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 3, totalDesks: 10),
        equals(const Color(0x1822C55E)), // 70% libre > 65%
      );

      // 🟡 35% à 65% libre (ex: 5/10 occupés = 50% libre) -> Orangée pastel douce (0x18F59E0B)
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 5, totalDesks: 10),
        equals(const Color(0x18F59E0B)),
      );
      // Bornes exactes 65% et 35%
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 35, totalDesks: 100),
        equals(const Color(0x18F59E0B)), // 65% libre
      );
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 65, totalDesks: 100),
        equals(const Color(0x18F59E0B)), // 35% libre
      );

      // 🔴 < 35% libre (ex: 8/10 occupés = 20% libre) -> Feutrée / ardoise douce (0x18EF4444)
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 8, totalDesks: 10),
        equals(const Color(0x18EF4444)),
      );
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 10, totalDesks: 10),
        equals(const Color(0x18EF4444)),
      );

      // Dark mode variations
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 2, totalDesks: 10, isDark: true),
        equals(const Color(0x2222C55E)),
      );
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 5, totalDesks: 10, isDark: true),
        equals(const Color(0x22F59E0B)),
      );
      expect(
        WorkspaceMapViewer.getRoomHeatmapColor(occupiedDesks: 8, totalDesks: 10, isDark: true),
        equals(const Color(0x22EF4444)),
      );
    });

    test('RoomOccupancyStats entity exposes correct percentages, counts and colors', () {
      const stats = RoomOccupancyStats(totalDesks: 8, occupiedDesks: 2);
      expect(stats.totalDesks, equals(8));
      expect(stats.occupiedDesks, equals(2));
      expect(stats.freeDesks, equals(6));
      expect(stats.occupancyRatio, closeTo(0.25, 0.001));
      expect(stats.freeRatio, closeTo(0.75, 0.001));
      expect(stats.occupancyPercentage, closeTo(25.0, 0.1));
      expect(stats.freePercentage, closeTo(75.0, 0.1));
      expect(stats.heatmapColor, equals(const Color(0x1822C55E)));
    });

    // ── 3. Tests widgets sur le rendu du plan et coloration thermique ────────
    testWidgets('WorkspaceMapViewer applies thermal floor colors and occupancy badges to rooms', (tester) async {
      tester.view.physicalSize = const Size(800, 800);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      // 3 Salles avec 4 bureaux chacune :
      // - SalleCalme : 0 occupés / 4 -> 100% libre (🟢 Vert)
      // - SalleModeree : 2 occupés / 4 -> 50% libre (🟡 Orange)
      // - SallePleine : 3 occupés / 4 -> 25% libre (🔴 Rouge)
      final features = [
        // SalleCalme
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'calm-01', 'name': 'SalleCalme-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[10.0, 10.0], [40.0, 10.0], [40.0, 30.0], [10.0, 30.0], [10.0, 10.0]]
            ]
          }
        },
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'calm-02', 'name': 'SalleCalme-02', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[50.0, 10.0], [80.0, 10.0], [80.0, 30.0], [50.0, 30.0], [50.0, 10.0]]
            ]
          }
        },
        // SalleModeree
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'mod-01', 'name': 'SalleModeree-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[10.0, 100.0], [40.0, 100.0], [40.0, 120.0], [10.0, 120.0], [10.0, 100.0]]
            ]
          }
        },
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'mod-02', 'name': 'SalleModeree-02', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[50.0, 100.0], [80.0, 100.0], [80.0, 120.0], [50.0, 120.0], [50.0, 100.0]]
            ]
          }
        },
        // SallePleine
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'busy-01', 'name': 'SallePleine-01', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[10.0, 200.0], [40.0, 200.0], [40.0, 220.0], [10.0, 220.0], [10.0, 200.0]]
            ]
          }
        },
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'busy-02', 'name': 'SallePleine-02', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[50.0, 200.0], [80.0, 200.0], [80.0, 220.0], [50.0, 220.0], [50.0, 200.0]]
            ]
          }
        },
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'busy-03', 'name': 'SallePleine-03', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[90.0, 200.0], [120.0, 200.0], [120.0, 220.0], [90.0, 220.0], [90.0, 200.0]]
            ]
          }
        },
        {
          'type': 'Feature',
          'properties': {'workspaceId': 'busy-04', 'name': 'SallePleine-04', 'workspaceType': 'Desk'},
          'geometry': {
            'type': 'Polygon',
            'coordinates': [
              [[130.0, 200.0], [160.0, 200.0], [160.0, 220.0], [130.0, 220.0], [130.0, 200.0]]
            ]
          }
        },
      ];

      final workspaces = [
        {'id': 'calm-01', 'name': 'SalleCalme-01', 'isBookable': true},
        {'id': 'calm-02', 'name': 'SalleCalme-02', 'isBookable': true},
        {'id': 'mod-01', 'name': 'SalleModeree-01', 'isBookable': true},
        {'id': 'mod-02', 'name': 'SalleModeree-02', 'isBookable': true},
        {'id': 'busy-01', 'name': 'SallePleine-01', 'isBookable': true},
        {'id': 'busy-02', 'name': 'SallePleine-02', 'isBookable': true},
        {'id': 'busy-03', 'name': 'SallePleine-03', 'isBookable': true},
        {'id': 'busy-04', 'name': 'SallePleine-04', 'isBookable': true},
      ];

      // Occupants:
      // SalleCalme: 0 occupant (2 bureaux au total -> 2 libres / 2 = 100%)
      // SalleModeree: 1 occupant sur 2 bureaux (1 libre / 2 = 50%)
      // SallePleine: 3 occupants sur 4 bureaux (1 libre / 4 = 25%)
      final occupants = <String, DeskOccupant>{
        'mod-01': DeskOccupant(occupantName: 'Occupant Mod 1', workspaceId: 'mod-01'),
        'busy-01': DeskOccupant(occupantName: 'Occupant Busy 1', workspaceId: 'busy-01'),
        'busy-02': DeskOccupant(occupantName: 'Occupant Busy 2', workspaceId: 'busy-02'),
        'busy-03': DeskOccupant(occupantName: 'Occupant Busy 3', workspaceId: 'busy-03'),
      };

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: features,
            workspaces: workspaces,
            allWorkspaces: workspaces,
            occupants: occupants,
            showRoomHeatmap: true,
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      // Vérifier l'état calculé de roomOccupancy
      final state = tester.state<WorkspaceMapViewerState>(find.byType(WorkspaceMapViewer));
      expect(state.showRoomHeatmap, isTrue);

      final calmStats = state.roomOccupancy['SalleCalme'];
      expect(calmStats, isNotNull);
      expect(calmStats!.totalDesks, equals(2));
      expect(calmStats.occupiedDesks, equals(0));
      expect(calmStats.freeRatio, equals(1.0));
      expect(calmStats.heatmapColor, equals(WorkspaceMapViewer.heatmapGreen));

      final modStats = state.roomOccupancy['SalleModeree'];
      expect(modStats, isNotNull);
      expect(modStats!.totalDesks, equals(2));
      expect(modStats.occupiedDesks, equals(1));
      expect(modStats.freeRatio, closeTo(0.50, 0.001));
      expect(modStats.heatmapColor, equals(WorkspaceMapViewer.heatmapOrange));

      final busyStats = state.roomOccupancy['SallePleine'];
      expect(busyStats, isNotNull);
      expect(busyStats!.totalDesks, equals(4));
      expect(busyStats.occupiedDesks, equals(3));
      expect(busyStats.freeRatio, closeTo(0.25, 0.001));
      expect(busyStats.heatmapColor, equals(WorkspaceMapViewer.heatmapRed));

      // Vérifier la présence des conteneurs de sol des 3 pièces
      final calmBoxFinder = find.byKey(const ValueKey('room_box_SalleCalme'));
      final modBoxFinder = find.byKey(const ValueKey('room_box_SalleModeree'));
      final busyBoxFinder = find.byKey(const ValueKey('room_box_SallePleine'));

      expect(calmBoxFinder, findsOneWidget);
      expect(modBoxFinder, findsOneWidget);
      expect(busyBoxFinder, findsOneWidget);

      // Vérifier les couleurs de sol appliquées
      final calmContainer = tester.widget<Container>(calmBoxFinder);
      final calmColor = (calmContainer.decoration as BoxDecoration).color!;

      final busyContainer = tester.widget<Container>(busyBoxFinder);
      final busyColor = (busyContainer.decoration as BoxDecoration).color!;

      // La salle calme (verte) a une composante verte dominante par rapport au rouge
      expect(calmColor.g, greaterThan(calmColor.r));
      // La salle pleine (rouge) a une composante rouge dominante
      expect(busyColor.r, greaterThan(busyColor.g));

      // Vérifier les étiquettes de salles et le ratio lisible
      expect(find.text('SalleCalme'), findsOneWidget);
      expect(find.text('2/2'), findsOneWidget);

      expect(find.text('SalleModeree'), findsOneWidget);
      expect(find.text('1/2'), findsOneWidget);

      expect(find.text('SallePleine'), findsOneWidget);
      expect(find.text('1/4'), findsOneWidget);
    });

    testWidgets('WorkspaceMapViewer showRoomHeatmap parameter and chip toggle work interactively', (tester) async {
      bool? toggledValue;

      await tester.pumpWidget(MaterialApp(
        theme: ThemeData.light(),
        home: Scaffold(
          body: WorkspaceMapViewer(
            features: [
              {
                'type': 'Feature',
                'properties': {'workspaceId': 'a-01', 'name': 'RoomA-01', 'workspaceType': 'Desk'},
                'geometry': {
                  'type': 'Polygon',
                  'coordinates': [
                    [[10.0, 10.0], [40.0, 10.0], [40.0, 30.0], [10.0, 30.0], [10.0, 10.0]]
                  ]
                }
              }
            ],
            workspaces: [
              {'id': 'a-01', 'name': 'RoomA-01', 'isBookable': true}
            ],
            showRoomHeatmap: true,
            onToggleHeatmap: (val) {
              toggledValue = val;
            },
            onSelected: (_) {},
          ),
        ),
      ));
      await tester.pumpAndSettle();

      final chipFinder = find.byKey(const ValueKey('toggle_heatmap_chip'));
      expect(chipFinder, findsOneWidget);

      final state = tester.state<WorkspaceMapViewerState>(find.byType(WorkspaceMapViewer));
      expect(state.showRoomHeatmap, isTrue);

      // Taper sur le chip pour désactiver la heatmap
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      expect(state.showRoomHeatmap, isFalse);
      expect(toggledValue, isFalse);

      // Le sol redevient la couleur surface par défaut (sans teinte thermique)
      final roomBox = tester.widget<Container>(find.byKey(const ValueKey('room_box_RoomA')));
      final decoration = roomBox.decoration as BoxDecoration;
      expect(decoration.color, isNotNull);

      // Taper à nouveau pour réactiver la heatmap
      await tester.tap(chipFinder);
      await tester.pumpAndSettle();

      expect(state.showRoomHeatmap, isTrue);
      expect(toggledValue, isTrue);
    });
  });
}
