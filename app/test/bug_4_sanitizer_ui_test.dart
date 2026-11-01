import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/screens/team_map_screen.dart';

class _FailingApiService extends RoomzApiService {
  final Exception failure;
  _FailingApiService(this.failure);

  @override
  Future<String?> refreshMyToken({bool force = false}) async {
    return 'valid-token';
  }

  @override
  Future<List<Map<String, dynamic>>> getFloorPlanData(
      String token, String siteId, String floorId) async {
    throw failure;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({
      'site_id': 'site-1',
      'floor_id': 'floor-1',
      'access_token': 'test-token',
    });
  });

  group('Bug #4 UI Error Sanitization on TeamMapScreen', () {
    testWidgets(
        'ClientException with HTTPS URL displays friendly French message and NEVER displays https://',
        (tester) async {
      final storage = StorageService();
      final failingApi = _FailingApiService(
        http.ClientException(
          'Failed host lookup: uri=https://api.my.roomz.io/api/floors/1',
        ),
      );

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: failingApi,
          storageService: storage,
          initialSiteId: 'site-1',
          initialFloorId: 'floor-1',
        ),
      ));
      await tester.pumpAndSettle();

      // The UI must display the clean, user-friendly connectivity message
      expect(
        find.text("Impossible de joindre le serveur. Veuillez vérifier votre connexion."),
        findsOneWidget,
      );

      // The UI must NEVER display the raw HTTPS URL or ClientException
      expect(find.textContaining('https://'), findsNothing);
      expect(find.textContaining('api.my.roomz.io'), findsNothing);
      expect(find.textContaining('ClientException'), findsNothing);
    });

    testWidgets(
        '401 Unauthorized displays Session expirée message and NEVER displays technical tokens',
        (tester) async {
      final storage = StorageService();
      final failingApi = _FailingApiService(
        Exception('401 Unauthorized: token expired at https://api.my.roomz.io/api/users'),
      );

      await tester.pumpWidget(MaterialApp(
        home: TeamMapScreen(
          apiService: failingApi,
          storageService: storage,
          initialSiteId: 'site-1',
          initialFloorId: 'floor-1',
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text("Session expirée. Veuillez vous reconnecter."),
        findsOneWidget,
      );
      expect(find.textContaining('https://'), findsNothing);
      expect(find.textContaining('401'), findsNothing);
    });
  });
}
