import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/main.dart';
import 'package:auto_roomzio/offline_state_manager.dart';
import 'package:auto_roomzio/widgets/offline_ribbon.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late OfflineStateManager stateManager;

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'refresh_token': 'mock_refresh_token',
      'workspace_name': 'Desk A-01',
      'automation_enabled': false,
      'theme_mode': 0,
      'theme_color': 0,
      'font_family': 0,
    });
    stateManager = OfflineStateManager.instance;
    stateManager.reset();
  });

  tearDown(() {
    stateManager.reset();
  });

  Widget buildTestAppShell({Widget? home, List<NavigatorObserver>? observers}) {
    return MaterialApp(
      navigatorObservers: observers ?? [],
      builder: (context, child) {
        return ValueListenableBuilder<bool>(
          valueListenable: stateManager.isOfflineNotifier,
          builder: (context, isOffline, _) {
            return Column(
              children: [
                Expanded(child: child ?? const SizedBox.shrink()),
                if (isOffline) const OfflineRibbon(),
              ],
            );
          },
        );
      },
      home: home ??
          const Scaffold(
            body: Center(child: Text('Home Screen')),
          ),
    );
  }

  group('OfflineRibbon Standalone Widget (R2.3)', () {
    testWidgets('renders exact mandatory text and wifi-off icon', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineRibbon(),
          ),
        ),
      );

      // Verify exact required text
      expect(
        find.text("Hors ligne • Affichage des dernières données synchronisées"),
        findsOneWidget,
      );
      expect(OfflineRibbon.ribbonText, "Hors ligne • Affichage des dernières données synchronisées");

      // Verify default icon
      expect(find.byIcon(Icons.wifi_off_rounded), findsOneWidget);
    });

    testWidgets('provides accessible live region semantics for screen readers', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineRibbon(),
          ),
        ),
      );

      final semanticsFinder = find.descendant(
        of: find.byType(OfflineRibbon),
        matching: find.byType(Semantics),
      );
      expect(semanticsFinder, findsAtLeastNWidgets(1));
      final semanticsWidget = tester.widget<Semantics>(semanticsFinder.first);
      expect(semanticsWidget.properties.liveRegion, isTrue);
      expect(semanticsWidget.properties.label, OfflineRibbon.ribbonText);
    });

    testWidgets('adapts styling in light and dark modes with high WCAG contrast', (tester) async {
      // Light mode test
      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: ThemeData.light(),
            child: const Scaffold(
              body: OfflineRibbon(),
            ),
          ),
        ),
      );

      final lightMaterial = tester.widget<Material>(
        find.descendant(of: find.byType(OfflineRibbon), matching: find.byType(Material)),
      );
      expect(lightMaterial.color, const Color(0xFFF59E0B)); // Amber 500

      // Dark mode test
      await tester.pumpWidget(
        MaterialApp(
          home: Theme(
            data: ThemeData.dark(),
            child: const Scaffold(
              body: OfflineRibbon(),
            ),
          ),
        ),
      );

      final darkMaterial = tester.widget<Material>(
        find.descendant(of: find.byType(OfflineRibbon), matching: find.byType(Material)),
      );
      expect(darkMaterial.color, const Color(0xFF92400E)); // Amber 800
    });

    testWidgets('wraps child widget cleanly when child parameter is passed', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: OfflineRibbon(
              child: Center(child: Text('Screen Content')),
            ),
          ),
        ),
      );

      expect(find.text('Screen Content'), findsOneWidget);
      expect(find.text("Hors ligne • Affichage des dernières données synchronisées"), findsOneWidget);
    });
  });

  group('OfflineRibbon Shell Integration across Navigation & Routes (R2.3)', () {
    testWidgets('initial state (isOffline == false): ribbon is hidden / not found', (tester) async {
      await tester.pumpWidget(buildTestAppShell());
      await tester.pumpAndSettle();

      expect(find.byType(OfflineRibbon), findsNothing);
      expect(find.text("Hors ligne • Affichage des dernières données synchronisées"), findsNothing);
      expect(find.text('Home Screen'), findsOneWidget);
    });

    testWidgets('offline triggered (isOffline == true): ribbon appears immediately', (tester) async {
      await tester.pumpWidget(buildTestAppShell());
      await tester.pumpAndSettle();

      expect(find.byType(OfflineRibbon), findsNothing);

      // Trigger offline
      stateManager.markOffline();
      await tester.pumpAndSettle();

      expect(find.byType(OfflineRibbon), findsOneWidget);
      expect(find.text("Hors ligne • Affichage des dernières données synchronisées"), findsOneWidget);
    });

    testWidgets('restoration (isOffline == false): ribbon disappears immediately', (tester) async {
      stateManager.markOffline();
      await tester.pumpWidget(buildTestAppShell());
      await tester.pumpAndSettle();

      expect(find.byType(OfflineRibbon), findsOneWidget);

      // Restore online
      stateManager.markOnline();
      await tester.pumpAndSettle();

      expect(find.byType(OfflineRibbon), findsNothing);
      expect(find.text("Hors ligne • Affichage des dernières données synchronisées"), findsNothing);
    });

    testWidgets('ribbon persists across route navigation when offline', (tester) async {
      late BuildContext savedContext;

      await tester.pumpWidget(
        buildTestAppShell(
          home: Builder(
            builder: (ctx) {
              savedContext = ctx;
              return Scaffold(
                appBar: AppBar(title: const Text('Page 1')),
                body: const Center(child: Text('Page 1 Body')),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Trigger offline on Page 1
      stateManager.markOffline();
      await tester.pumpAndSettle();

      expect(find.text('Page 1 Body'), findsOneWidget);
      expect(find.byType(OfflineRibbon), findsOneWidget);

      // Push Page 2
      Navigator.of(savedContext).push(
        MaterialPageRoute(
          builder: (ctx2) => Scaffold(
            appBar: AppBar(title: const Text('Page 2')),
            body: const Center(child: Text('Page 2 Body')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify ribbon is still visible on Page 2
      expect(find.text('Page 2 Body'), findsOneWidget);
      expect(find.byType(OfflineRibbon), findsOneWidget);
      expect(find.text("Hors ligne • Affichage des dernières données synchronisées"), findsOneWidget);

      // Push Page 3
      Navigator.of(savedContext).push(
        MaterialPageRoute(
          builder: (ctx3) => Scaffold(
            appBar: AppBar(title: const Text('Page 3')),
            body: const Center(child: Text('Page 3 Body')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Verify ribbon on Page 3
      expect(find.text('Page 3 Body'), findsOneWidget);
      expect(find.byType(OfflineRibbon), findsOneWidget);

      // Pop back to Page 2
      Navigator.of(savedContext).pop();
      await tester.pumpAndSettle();

      expect(find.text('Page 2 Body'), findsOneWidget);
      expect(find.byType(OfflineRibbon), findsOneWidget);

      // Pop back to Page 1
      Navigator.of(savedContext).pop();
      await tester.pumpAndSettle();

      expect(find.text('Page 1 Body'), findsOneWidget);
      expect(find.byType(OfflineRibbon), findsOneWidget);

      // Switch to online while on Page 1
      stateManager.markOnline();
      await tester.pumpAndSettle();

      expect(find.byType(OfflineRibbon), findsNothing);
    });

    testWidgets('dialog presentation does not dismiss or displace the ribbon', (tester) async {
      await tester.pumpWidget(
        buildTestAppShell(
          home: Builder(
            builder: (ctx) {
              return Scaffold(
                body: Center(
                  child: ElevatedButton(
                    onPressed: () {
                      showDialog(
                        context: ctx,
                        builder: (_) => const AlertDialog(
                          title: Text('Test Dialog'),
                          content: Text('Dialog Content'),
                        ),
                      );
                    },
                    child: const Text('Open Dialog'),
                  ),
                ),
              );
            },
          ),
        ),
      );
      await tester.pumpAndSettle();

      stateManager.markOffline();
      await tester.pumpAndSettle();

      // Tap open dialog
      await tester.tap(find.text('Open Dialog'));
      await tester.pumpAndSettle();

      expect(find.text('Test Dialog'), findsOneWidget);
      expect(find.byType(OfflineRibbon), findsOneWidget);
      expect(find.text("Hors ligne • Affichage des dernières données synchronisées"), findsOneWidget);
    });

    testWidgets('renders cleanly without overflow across diverse text scalers and screen sizes', (tester) async {
      tester.view.physicalSize = const Size(360, 640); // small phone
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.resetPhysicalSize);

      await tester.pumpWidget(
        MaterialApp(
          builder: (context, child) {
            return MediaQuery(
              data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(1.35)),
              child: Column(
                children: [
                  Expanded(child: child ?? const SizedBox.shrink()),
                  const OfflineRibbon(),
                ],
              ),
            );
          },
          home: const Scaffold(
            body: Center(child: Text('Scaled UI')),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.byType(OfflineRibbon), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  group('MyApp Global Shell Integration (R2.3 in main.dart)', () {
    testWidgets('MyApp mounts OfflineRibbon globally when offline', (tester) async {
      stateManager.markOffline();
      await tester.pumpWidget(const MyApp());
      await tester.pump();

      expect(find.byType(OfflineRibbon), findsOneWidget);
      expect(find.text(OfflineRibbon.ribbonText), findsOneWidget);

      stateManager.markOnline();
      await tester.pump();

      expect(find.byType(OfflineRibbon), findsNothing);
      expect(find.text(OfflineRibbon.ribbonText), findsNothing);
    });
  });
}
