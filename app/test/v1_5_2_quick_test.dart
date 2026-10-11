import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/storage_service.dart';
import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/screens/login_screen.dart';
import 'package:auto_roomzio/widgets/colleague_selection_dialog.dart';

class FakeSecureStorage extends FlutterSecureStorage {
  final Map<String, String> map;
  final bool throwOnOperations;

  FakeSecureStorage({
    Map<String, String>? initialData,
    this.throwOnOperations = false,
  }) : map = initialData != null ? Map.from(initialData) : {};

  @override
  Future<void> write({
    required String key,
    required String? value,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnOperations) throw MissingPluginException();
    if (value == null) {
      map.remove(key);
    } else {
      map[key] = value;
    }
  }

  @override
  Future<String?> read({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnOperations) throw MissingPluginException();
    return map[key];
  }

  @override
  Future<void> delete({
    required String key,
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnOperations) throw MissingPluginException();
    map.remove(key);
  }

  @override
  Future<void> deleteAll({
    AppleOptions? iOptions,
    AndroidOptions? aOptions,
    LinuxOptions? lOptions,
    WebOptions? webOptions,
    AppleOptions? mOptions,
    WindowsOptions? wOptions,
  }) async {
    if (throwOnOperations) throw MissingPluginException();
    map.clear();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('v1.5.2 Quick Tests Suite (< 5s, 100% Anonymized)', () {
    // -------------------------------------------------------------------------
    // 1. Validation form web (email valide vs invalide)
    // -------------------------------------------------------------------------
    testWidgets('1. Web login form: validates email format and blocks invalid submissions', (tester) async {
      tester.view.physicalSize = const Size(1024, 1024);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() {
        tester.view.resetPhysicalSize();
        tester.view.resetDevicePixelRatio();
      });

      final fakeStorage = FakeSecureStorage();
      final storage = StorageService(secureStorage: fakeStorage);
      bool apiLoginCalled = false;

      final mockApi = RoomzApiService(
        client: MockClient((req) async {
          if (req.url.path.contains('/login') || req.url.path.contains('/token')) {
            apiLoginCalled = true;
          }
          return http.Response('{"access_token": "token-123"}', 200);
        }),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: LoginScreen(
            forceWebLayout: true,
            ignoreUrlToken: true,
            storageService: storage,
            apiService: mockApi,
          ),
        ),
      );
      await tester.pumpAndSettle();

      final emailField = find.widgetWithText(TextFormField, 'Email professionnel');
      final passwordField = find.widgetWithText(TextFormField, 'Mot de passe Roomz');
      final submitButton = find.widgetWithText(ElevatedButton, 'Se connecter');

      expect(emailField, findsOneWidget);
      expect(passwordField, findsOneWidget);
      expect(submitButton, findsOneWidget);

      await tester.ensureVisible(submitButton);

      // A. Invalide: email malformé sans domaine
      await tester.enterText(emailField, 'invalid-email-format');
      await tester.enterText(passwordField, 'validPassword123');
      await tester.tap(submitButton, warnIfMissed: false);
      await tester.pump();

      expect(find.text('Veuillez saisir une adresse email valide.'), findsOneWidget);
      expect(apiLoginCalled, isFalse);

      // B. Invalide: email vide
      await tester.enterText(emailField, '');
      await tester.tap(submitButton, warnIfMissed: false);
      await tester.pump();

      expect(find.text('Veuillez saisir une adresse email valide.'), findsOneWidget);
      expect(apiLoginCalled, isFalse);

      // C. Valide: adresse email conforme
      await tester.enterText(emailField, 'alex.martin@example.com');
      await tester.tap(submitButton, warnIfMissed: false);
      await tester.pump();

      // Erreur de validation d'email n'apparaît plus
      expect(find.text('Veuillez saisir une adresse email valide.'), findsNothing);
    });

    // -------------------------------------------------------------------------
    // 2. Mémorisation de l'email dans StorageService
    // -------------------------------------------------------------------------
    test('2. StorageService: preserves remembered email across clearAllData', () async {
      final fakeStorage = FakeSecureStorage();
      final storage = StorageService(secureStorage: fakeStorage);

      // Activer la mémorisation et enregistrer un email anonymisé
      await storage.saveRememberEmail(true);
      await storage.saveSavedEmail('alex.martin@example.com');

      expect(await storage.getRememberEmail(), isTrue);
      expect(await storage.getSavedEmail(), equals('alex.martin@example.com'));

      // clearAllData() doit préserver l'email mémorisé si rememberEmail == true
      await storage.clearAllData();
      expect(await storage.getRememberEmail(), isTrue);
      expect(await storage.getSavedEmail(), equals('alex.martin@example.com'));

      // Désactivation de la mémorisation puis déconnexion / clearAllData
      await storage.saveRememberEmail(false);
      await storage.clearAllData();

      expect(await storage.getSavedEmail(), isNull);
    });

    // -------------------------------------------------------------------------
    // 3. mergeFavoriteColleagues qui préserve un collègue externe local
    // -------------------------------------------------------------------------
    test('3. mergeFavoriteColleagues: preserves local external colleague and integrates remote favorites', () async {
      final fakeStorage = FakeSecureStorage();
      final storage = StorageService(secureStorage: fakeStorage);

      final localExternalColleague = Colleague(
        id: 'ext_local_01',
        name: 'Alex Martin',
        email: 'alex.martin@example.com',
        isFavorite: true,
      );

      // Enregistrer le collègue local existant
      await storage.saveFavoriteColleagues([localExternalColleague]);

      // Nouveaux favoris renvoyés par l'API
      final remoteFavorites = [
        Colleague(
          id: 'usr_remote_01',
          name: 'Taylor Smith',
          email: 'taylor.smith@example.com',
          isFavorite: true,
          favoriteId: 'fav_remote_99',
        ),
      ];

      // Fusionner les favoris
      await storage.mergeFavoriteColleagues(remoteFavorites);

      final mergedFavorites = await storage.getFavoriteColleagues();
      expect(mergedFavorites.length, equals(2));

      // Vérifier que le collègue local externe a été strictement préservé
      final hasLocal = mergedFavorites.any(
        (c) => c.id == 'ext_local_01' && c.name == 'Alex Martin' && c.email == 'alex.martin@example.com',
      );
      expect(hasLocal, isTrue);

      // Vérifier que le collègue distant a été ajouté
      final hasRemote = mergedFavorites.any(
        (c) => c.id == 'usr_remote_01' && c.name == 'Taylor Smith' && c.favoriteId == 'fav_remote_99',
      );
      expect(hasRemote, isTrue);
    });

    // -------------------------------------------------------------------------
    // 4. Détection des collègues déjà assis dans un dialogue ou une liste
    // -------------------------------------------------------------------------
    testWidgets('4. ColleagueSelectionDialog: detects already seated colleagues and prevents selection', (tester) async {
      final seatedColleague = Colleague(
        id: 'usr_seated_01',
        name: 'Alex Martin',
        email: 'alex.martin@example.com',
        isFavorite: true,
      );

      final unseatedColleague = Colleague(
        id: 'usr_free_02',
        name: 'Taylor Smith',
        email: 'taylor.smith@example.com',
        isFavorite: true,
      );

      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': jsonEncode([
          seatedColleague.toJson(),
          unseatedColleague.toJson(),
        ]),
      });

      Colleague? selectedResult;
      final mockApi = RoomzApiService(
        client: MockClient((req) async => http.Response('[]', 200)),
      );

      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: ColleagueSelectionDialog(
              date: '2026-10-15',
              apiService: mockApi,
              alreadySeatedColleagues: {'usr_seated_01': 'Desk A-01'},
              onColleagueSelected: (c) => selectedResult = c,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Les deux collègues sont présents dans la liste
      expect(find.text('Alex Martin'), findsOneWidget);
      expect(find.text('Taylor Smith'), findsOneWidget);

      // Le collègue assis affiche sa place occupée en sous-titre
      expect(find.text('A déjà une place (Desk A-01)'), findsOneWidget);

      // Le collègue libre n'affiche pas la mention d'occupation
      expect(find.text('taylor.smith@example.com'), findsOneWidget);

      // Clic sur le collègue déjà assis (onTap désactivé, empêche la réservation)
      await tester.tap(find.text('Alex Martin'), warnIfMissed: false);
      await tester.pumpAndSettle();

      // Aucun dialogue de confirmation de réservation n'est ouvert pour Alex Martin
      expect(find.text('Confirmer la réservation'), findsNothing);
      expect(selectedResult, isNull);
    });
  });
}
