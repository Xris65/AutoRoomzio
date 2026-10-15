import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:auto_roomzio/widgets/mini_map_overlay.dart';
import 'package:auto_roomzio/widgets/workspace_map_viewer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('MiniMapOverlay Unit & Widget Tests', () {
    testWidgets('Renders collapsed by default as a radar toggle button', (tester) async {
      final controller = TransformationController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniMapOverlay(
                transformationController: controller,
                viewportSize: const Size(400, 600),
                mapSize: const Size(1200, 800),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_toggle_button')), findsOneWidget);
      expect(find.byIcon(Icons.radar), findsOneWidget);
      expect(find.byKey(const Key('mini_map_panel')), findsNothing);
    });

    testWidgets('Tapping toggle button expands the mini-map panel, and collapse button closes it', (tester) async {
      final controller = TransformationController();
      addTearDown(controller.dispose);

      bool? lastExpandedState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniMapOverlay(
                transformationController: controller,
                viewportSize: const Size(400, 600),
                mapSize: const Size(1200, 800),
                onExpansionChanged: (val) => lastExpandedState = val,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Tap to expand
      await tester.tap(find.byKey(const Key('mini_map_toggle_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_panel')), findsOneWidget);
      expect(find.byKey(const Key('mini_map_canvas')), findsOneWidget);
      expect(find.text('Radar'), findsOneWidget);
      expect(lastExpandedState, isTrue);

      // Tap close button to collapse
      await tester.tap(find.byKey(const Key('mini_map_collapse_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_panel')), findsNothing);
      expect(find.byKey(const Key('mini_map_toggle_button')), findsOneWidget);
      expect(lastExpandedState, isFalse);
    });

    testWidgets('Initially expanded property opens panel directly', (tester) async {
      final controller = TransformationController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniMapOverlay(
                transformationController: controller,
                viewportSize: const Size(400, 600),
                mapSize: const Size(1200, 800),
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_panel')), findsOneWidget);
      expect(find.byKey(const Key('mini_map_canvas')), findsOneWidget);
    });

    testWidgets('Tapping on mini-map canvas repositions the TransformationController camera', (tester) async {
      final controller = TransformationController();
      addTearDown(controller.dispose);

      // Initialize with identity matrix
      controller.value = Matrix4.identity();

      bool targetSelected = false;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniMapOverlay(
                transformationController: controller,
                viewportSize: const Size(400, 400),
                mapSize: const Size(1000, 1000),
                initiallyExpanded: true,
                miniMapWidth: 160.0,
                miniMapHeight: 120.0,
                onTargetSelected: () => targetSelected = true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final initialDx = controller.value.entry(0, 3);
      final initialDy = controller.value.entry(1, 3);
      expect(initialDx, equals(0.0));
      expect(initialDy, equals(0.0));

      // Tap on the mini-map canvas
      final canvasFinder = find.byKey(const Key('mini_map_canvas'));
      expect(canvasFinder, findsOneWidget);

      final canvasCenter = tester.getCenter(canvasFinder);
      await tester.tapAt(canvasCenter);
      await tester.pumpAndSettle();

      final updatedDx = controller.value.entry(0, 3);
      final updatedDy = controller.value.entry(1, 3);

      // Since canvas center corresponds to map center (500, 500) and viewport is 400x400,
      // dx should be (400/2) - (500 * 1.0) = -300
      expect(updatedDx, closeTo(-300.0, 5.0));
      expect(updatedDy, closeTo(-300.0, 5.0));
      expect(targetSelected, isTrue);
    });

    testWidgets('Dragging on mini-map canvas smoothly pans the camera', (tester) async {
      final controller = TransformationController();
      addTearDown(controller.dispose);
      controller.value = Matrix4.identity();

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniMapOverlay(
                transformationController: controller,
                viewportSize: const Size(500, 500),
                mapSize: const Size(1000, 1000),
                initiallyExpanded: true,
                miniMapWidth: 160.0,
                miniMapHeight: 120.0,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      final canvasFinder = find.byKey(const Key('mini_map_canvas'));
      final topLeft = tester.getTopLeft(canvasFinder) + const Offset(10, 10);
      final target = topLeft + const Offset(30, 20);

      // Drag gesture across the mini-map
      final gesture = await tester.startGesture(topLeft);
      await tester.pump();
      await gesture.moveTo(target);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      final newDx = controller.value.entry(0, 3);
      final newDy = controller.value.entry(1, 3);

      // The translation must have updated and not be 0
      expect(newDx, isNot(equals(0.0)));
      expect(newDy, isNot(equals(0.0)));
    });

    testWidgets('Renders rooms and desks silhouettes without throwing', (tester) async {
      final controller = TransformationController();
      addTearDown(controller.dispose);

      const rooms = [
        Rect.fromLTWH(50, 50, 200, 150),
        Rect.fromLTWH(300, 50, 200, 150),
        Rect.fromLTWH(50, 250, 450, 200),
      ];
      const desks = [
        Rect.fromLTWH(60, 60, 40, 25),
        Rect.fromLTWH(110, 60, 40, 25),
        Rect.fromLTWH(310, 60, 40, 25),
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniMapOverlay(
                transformationController: controller,
                viewportSize: const Size(600, 400),
                mapSize: const Size(800, 600),
                rooms: rooms,
                desks: desks,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_panel')), findsOneWidget);
      expect(find.byKey(const Key('mini_map_canvas')), findsOneWidget);
    });

    testWidgets('Resilient against zero/negative dimensions and empty lists', (tester) async {
      final controller = TransformationController();
      addTearDown(controller.dispose);

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(
              child: MiniMapOverlay(
                transformationController: controller,
                viewportSize: Size.zero,
                mapSize: Size.zero,
                initiallyExpanded: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_panel')), findsOneWidget);

      // Tapping with zero dimensions must not crash
      final canvasFinder = find.byKey(const Key('mini_map_canvas'));
      await tester.tap(canvasFinder);
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
    });

    testWidgets('WorkspaceMapViewer integrates MiniMapOverlay with showMiniMap flag', (tester) async {
      final sampleFeatures = [
        {
          'geometry': {
            'coordinates': [
              [
                [0.0, 0.0],
                [100.0, 0.0],
                [100.0, 80.0],
                [0.0, 80.0],
                [0.0, 0.0],
              ]
            ]
          },
          'properties': {
            'workspaceId': 'desk-1',
            'workspaceType': 'Desk',
            'name': 'Salle Nord-01',
          }
        }
      ];

      // 1. With showMiniMap = true (default)
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: WorkspaceMapViewer(
                features: sampleFeatures,
                workspaces: const [
                  {'id': 'desk-1', 'name': 'Salle Nord-01'}
                ],
                onSelected: (_) {},
                showMiniMap: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Radar toggle button should be present
      expect(find.byKey(const Key('mini_map_toggle_button')), findsOneWidget);

      // Tap radar toggle to expand mini-map
      await tester.tap(find.byKey(const Key('mini_map_toggle_button')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_panel')), findsOneWidget);

      // 2. With showMiniMap = false
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: WorkspaceMapViewer(
                features: sampleFeatures,
                workspaces: const [
                  {'id': 'desk-1', 'name': 'Salle Nord-01'}
                ],
                onSelected: (_) {},
                showMiniMap: false,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_toggle_button')), findsNothing);
      expect(find.byKey(const Key('mini_map_panel')), findsNothing);
    });

    testWidgets('Tapping outside the expanded mini-map collapses it automatically', (tester) async {
      final controller = TransformationController();
      addTearDown(controller.dispose);

      bool? expandedState;

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Stack(
              children: [
                Center(
                  child: MiniMapOverlay(
                    transformationController: controller,
                    viewportSize: const Size(400, 600),
                    mapSize: const Size(1200, 800),
                    initiallyExpanded: true,
                    onExpansionChanged: (val) => expandedState = val,
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_panel')), findsOneWidget);

      // Tap far outside the mini-map panel (top-left of screen)
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('mini_map_panel')), findsNothing);
      expect(find.byKey(const Key('mini_map_toggle_button')), findsOneWidget);
      expect(expandedState, isFalse);
    });

    testWidgets('WorkspaceMapViewer positions MiniMapOverlay on left (left: 16) and closes on click outside or zoom button', (tester) async {
      final sampleFeatures = [
        {
          'geometry': {
            'coordinates': [
              [
                [0.0, 0.0],
                [100.0, 0.0],
                [100.0, 80.0],
                [0.0, 80.0],
                [0.0, 0.0],
              ]
            ]
          },
          'properties': {
            'workspaceId': 'desk-1',
            'workspaceType': 'Desk',
            'name': 'Salle Nord-01',
          }
        }
      ];

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: SizedBox(
              width: 500,
              height: 500,
              child: WorkspaceMapViewer(
                features: sampleFeatures,
                workspaces: const [
                  {'id': 'desk-1', 'name': 'Salle Nord-01'}
                ],
                onSelected: (_) {},
                showMiniMap: true,
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Check positioned on left
      final positionedFinder = find.ancestor(
        of: find.byType(MiniMapOverlay),
        matching: find.byType(Positioned),
      );
      expect(positionedFinder, findsOneWidget);
      final positioned = tester.widget<Positioned>(positionedFinder);
      expect(positioned.left, equals(16.0));
      expect(positioned.right, isNull);
      expect(positioned.bottom, equals(16.0));

      // Open minimap
      await tester.tap(find.byKey(const Key('mini_map_toggle_button')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mini_map_panel')), findsOneWidget);

      // Tapping inside the minimap canvas DOES NOT close it
      final canvasFinder = find.byKey(const Key('mini_map_canvas'));
      await tester.tap(canvasFinder);
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mini_map_panel')), findsOneWidget);

      // Tapping on another button (e.g. zoomIn FAB on the right) closes it
      await tester.tap(find.widgetWithIcon(FloatingActionButton, Icons.add));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('mini_map_panel')), findsNothing);
      expect(find.byKey(const Key('mini_map_toggle_button')), findsOneWidget);
    });
  });
}
