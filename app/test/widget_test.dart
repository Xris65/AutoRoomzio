import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/main.dart';
import 'package:auto_roomzio/screens/home_screen.dart';
import 'package:auto_roomzio/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'refresh_token': 'mock_refresh_token',
      'workspace_name': 'Desk A-01',
      'automation_enabled': false,
      'theme_mode': 0, // system
      'theme_color': 0,
      'font_family': 0,
    });
  });

  group('AutoRoomzio Smoke and Sanity Tests', () {
    testWidgets('pumps MyApp and displays root MaterialApp and HomeScreen', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pump();

      expect(find.byType(MaterialApp), findsOneWidget);
      expect(find.byType(HomeScreen), findsOneWidget);

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.title, equals('AutoRoomzio'));
    });

    testWidgets('theme and color notifiers react properly in MyApp', (WidgetTester tester) async {
      await tester.pumpWidget(const MyApp());
      await tester.pump();

      // Change theme color
      themeColorNotifier.value = 2; // deepPurple
      await tester.pump();

      final materialApp = tester.widget<MaterialApp>(find.byType(MaterialApp));
      expect(materialApp.theme?.colorScheme.primary, isNotNull);

      // Reset
      themeColorNotifier.value = 0;
      await tester.pump();
    });

    test('StorageService initializes correctly with mock SharedPreferences', () async {
      final storage = StorageService();
      final workspace = await storage.getWorkspaceName();
      final token = await storage.getRefreshToken();
      final autoEnabled = await storage.getAutomationEnabled();

      expect(workspace, equals('Desk A-01'));
      expect(token, equals('mock_refresh_token'));
      expect(autoEnabled, isFalse);
    });
  });
}
