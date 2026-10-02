import 'dart:convert';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:auto_roomzio/models/colleague.dart';
import 'package:auto_roomzio/storage_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // =========================================================================
  // SECTION 1: Adversarial Stress-Testing of Colleague Domain Model
  // =========================================================================
  group('Adversarial M2: Colleague Initials Calculation Stress-Testing', () {
    test('Boundary edge case: single names ("Cher", "Madonna", single character)', () {
      expect(const Colleague(id: '1', name: 'Cher').initials, equals('C'));
      expect(const Colleague(id: '2', name: 'Madonna').initials, equals('M'));
      expect(const Colleague(id: '3', name: 'Z').initials, equals('Z'));
      expect(const Colleague(id: '4', name: 'a').initials, equals('A'));
    });

    test('Boundary edge case: accented names ("Élodie François", "Àlex Ömer")', () {
      expect(const Colleague(id: '1', name: 'Élodie François').initials, equals('ÉF'));
      expect(const Colleague(id: '2', name: 'Àlex Ömer').initials, equals('ÀÖ'));
      expect(const Colleague(id: '3', name: 'çois durand').initials, equals('ÇD'));
    });

    test('Boundary edge case: particle names ("Jean de La Fontaine", "Charles Louis de Montesquieu")', () {
      // First name initial + Last name initial (Fontaine / Montesquieu)
      expect(const Colleague(id: '1', name: 'Jean de La Fontaine').initials, equals('JF'));
      expect(const Colleague(id: '2', name: 'Charles Louis de Montesquieu').initials, equals('CM'));
      expect(const Colleague(id: '3', name: 'Ludwig van Beethoven').initials, equals('LB'));
    });

    test('Boundary edge case: hyphenated names ("Jean-Paul Belmondo", "Jean-Paul")', () {
      // Split on whitespace: "Jean-Paul" is first token, "Belmondo" is last token
      expect(const Colleague(id: '1', name: 'Jean-Paul Belmondo').initials, equals('JB'));
      // Single hyphenated name: first token initial is 'J'
      expect(const Colleague(id: '2', name: 'Jean-Paul').initials, equals('J'));
      expect(const Colleague(id: '3', name: 'Anne-Sophie Lapix').initials, equals('AL'));
    });

    test('Boundary edge case: leading, trailing, and excessive internal whitespace', () {
      expect(const Colleague(id: '1', name: '   Alice   ').initials, equals('A'));
      expect(const Colleague(id: '2', name: '\t\tBob   \t   Marley\n\n').initials, equals('BM'));
      expect(const Colleague(id: '3', name: '   John    William    Smith   ').initials, equals('JS'));
    });

    test('Boundary edge case: empty strings, pure whitespace, and non-alphabetic characters', () {
      expect(const Colleague(id: '1', name: '').initials, equals('?'));
      expect(const Colleague(id: '2', name: '   ').initials, equals('?'));
      expect(const Colleague(id: '3', name: '\t\n\r  ').initials, equals('?'));
      expect(const Colleague(id: '4', name: '123 456').initials, equals('14'));
      expect(const Colleague(id: '5', name: '-- --').initials, equals('--'));
    });

    test('Boundary edge case: emojis and unicode symbols in names', () {
      // Name starting with emoji / symbol: verify calculation executes without uncaught exception
      const c1 = Colleague(id: '1', name: '🤖 Robot');
      expect(c1.initials, isNotEmpty);

      const c2 = Colleague(id: '2', name: '⭐');
      expect(c2.initials, isNotEmpty);
    });
  });

  group('Adversarial M2: Colleague Serialization & Deserialization Robustness', () {
    test('fromJson resilience against empty map, null fields, and unknown keys', () {
      final cEmpty = Colleague.fromJson({});
      expect(cEmpty.id, equals(''));
      expect(cEmpty.name, equals('Collègue'));
      expect(cEmpty.email, equals(''));
      expect(cEmpty.isFavorite, isFalse);
      expect(cEmpty.deskName, isNull);
      expect(cEmpty.roomName, isNull);
      expect(cEmpty.avatarUrl, isNull);

      final cNulls = Colleague.fromJson({
        'id': null,
        'userId': null,
        'name': null,
        'displayName': null,
        'email': null,
        'mail': null,
        'isFavorite': null,
        'favorite': null,
        'deskName': null,
        'roomName': null,
        'avatarUrl': null,
        'unknown_field_1': 9999,
        'nested_object': {'a': 1, 'b': 'c'},
      });
      expect(cNulls.id, equals(''));
      expect(cNulls.name, equals('Collègue'));
      expect(cNulls.email, equals(''));
      expect(cNulls.isFavorite, isFalse);
    });

    test('fromJson handles non-string numeric or boolean representations of IDs and names', () {
      final cTypes = Colleague.fromJson({
        'id': 10099,
        'name': 404,
        'email': 'numeric@test.com',
        'isFavorite': true,
      });
      expect(cTypes.id, equals('10099'));
      expect(cTypes.name, equals('404'));
      expect(cTypes.email, equals('numeric@test.com'));
      expect(cTypes.isFavorite, isTrue);
    });

    test('toJson produces clean JSON encodable map omitting null fields', () {
      const cMinimal = Colleague(id: 'u1', name: 'Min User');
      final jsonMap = cMinimal.toJson();

      expect(jsonMap.containsKey('id'), isTrue);
      expect(jsonMap.containsKey('name'), isTrue);
      expect(jsonMap.containsKey('email'), isTrue);
      expect(jsonMap.containsKey('isFavorite'), isTrue);
      expect(jsonMap.containsKey('deskName'), isFalse);
      expect(jsonMap.containsKey('roomName'), isFalse);
      expect(jsonMap.containsKey('avatarUrl'), isFalse);

      final encoded = jsonEncode(jsonMap);
      expect(encoded, isNotEmpty);
      final decoded = jsonDecode(encoded);
      expect(decoded['name'], equals('Min User'));
    });

    test('Serialization roundtrip preserves full state across jsonEncode and jsonDecode', () {
      const original = Colleague(
        id: 'usr-complete-99',
        name: 'Marie-Antoinette de Habsbourg',
        email: 'marie@versailles.fr',
        isFavorite: true,
        deskName: 'DS-VERS-2-01',
        roomName: 'Galerie des Glaces',
        avatarUrl: 'https://images.example.com/avatar.png',
      );

      final encoded = jsonEncode(original.toJson());
      final restored = Colleague.fromJson(jsonDecode(encoded) as Map<String, dynamic>);
      expect(restored, equals(original));
      expect(restored.hashCode, equals(original.hashCode));
    });
  });

  group('Adversarial M2: Colleague Equality and HashCode Contract', () {
    test('Reflexivity, Symmetry, and Transitivity', () {
      const a = Colleague(id: '1', name: 'Alice', email: 'a@a.com', isFavorite: true, deskName: 'D1');
      const b = Colleague(id: '1', name: 'Alice', email: 'a@a.com', isFavorite: true, deskName: 'D1');
      const c = Colleague(id: '1', name: 'Alice', email: 'a@a.com', isFavorite: true, deskName: 'D1');

      // Reflexivity
      expect(a == a, isTrue);
      // Symmetry
      expect(a == b, isTrue);
      expect(b == a, isTrue);
      // Transitivity
      expect(a == b && b == c, isTrue);
      expect(a == c, isTrue);
      // HashCode consistency
      expect(a.hashCode, equals(b.hashCode));
      expect(b.hashCode, equals(c.hashCode));
    });

    test('Differentiation across each individual field', () {
      const base = Colleague(
        id: '1',
        name: 'Jean',
        email: 'j@a.com',
        isFavorite: false,
        deskName: 'D1',
        roomName: 'R1',
        avatarUrl: 'A1',
      );

      expect(base == base.copyWith(id: '2'), isFalse);
      expect(base.hashCode != base.copyWith(id: '2').hashCode, isTrue);

      expect(base == base.copyWith(name: 'Paul'), isFalse);
      expect(base.hashCode != base.copyWith(name: 'Paul').hashCode, isTrue);

      expect(base == base.copyWith(email: 'p@a.com'), isFalse);
      expect(base.hashCode != base.copyWith(email: 'p@a.com').hashCode, isTrue);

      expect(base == base.copyWith(isFavorite: true), isFalse);
      expect(base.hashCode != base.copyWith(isFavorite: true).hashCode, isTrue);

      expect(base == base.copyWith(deskName: 'D2'), isFalse);
      expect(base.hashCode != base.copyWith(deskName: 'D2').hashCode, isTrue);

      expect(base == base.copyWith(roomName: 'R2'), isFalse);
      expect(base.hashCode != base.copyWith(roomName: 'R2').hashCode, isTrue);

      expect(base == base.copyWith(avatarUrl: 'A2'), isFalse);
      expect(base.hashCode != base.copyWith(avatarUrl: 'A2').hashCode, isTrue);
    });

    test('Set and Map collection operations behave identically for matching Colleague instances', () {
      const c1 = Colleague(id: '1', name: 'User', email: 'u@corp.com', isFavorite: true);
      const c2 = Colleague(id: '1', name: 'User', email: 'u@corp.com', isFavorite: true);

      final set = <Colleague>{c1};
      expect(set.contains(c2), isTrue);
      expect(set.length, equals(1));
      set.add(c2);
      expect(set.length, equals(1)); // No duplicate added in Set

      final map = <Colleague, String>{c1: 'Data'};
      expect(map[c2], equals('Data'));
    });
  });

  // =========================================================================
  // SECTION 2: Adversarial Stress-Testing of StorageService Favorites
  // =========================================================================
  group('Adversarial M2: StorageService Malformed Data Resilience', () {
    late StorageService storage;

    setUp(() {
      storage = StorageService();
    });

    test('getFavoriteColleagues returns empty list on invalid JSON syntax', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': '{"broken_json": [true,',
      });
      final result = await storage.getFavoriteColleagues();
      expect(result, isEmpty);
    });

    test('getFavoriteColleagues returns empty list when stored JSON is a JSON Object (Map) instead of List', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': '{"id": "usr-1", "name": "Solo Object"}',
      });
      final result = await storage.getFavoriteColleagues();
      expect(result, isEmpty);
    });

    test('getFavoriteColleagues returns empty list when stored value is JSON string, number, or boolean', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': '"just a string"',
      });
      expect(await storage.getFavoriteColleagues(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': '12345',
      });
      expect(await storage.getFavoriteColleagues(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': 'true',
      });
      expect(await storage.getFavoriteColleagues(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': 'null',
      });
      expect(await storage.getFavoriteColleagues(), isEmpty);
    });

    test('getFavoriteColleagues returns empty list when stored value is an empty string or whitespace', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': '',
      });
      expect(await storage.getFavoriteColleagues(), isEmpty);

      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': '    ',
      });
      expect(await storage.getFavoriteColleagues(), isEmpty);
    });

    test('getFavoriteColleagues returns empty list when stored JSON list contains non-map primitives', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': '[1, 2, "three", true]',
      });
      final result = await storage.getFavoriteColleagues();
      expect(result, isEmpty);
    });
  });

  group('Adversarial M2: StorageService Idempotency and Mutation Robustness', () {
    late StorageService storage;

    setUp(() {
      SharedPreferences.setMockInitialValues({});
      storage = StorageService();
    });

    test('addFavoriteColleague is idempotent across multiple repetitive calls', () async {
      const colleague = Colleague(
        id: 'u-idempotent-1',
        name: 'Isaac Newton',
        email: 'isaac@cambridge.edu',
      );

      for (int i = 0; i < 5; i++) {
        await storage.addFavoriteColleague(colleague);
      }

      final list = await storage.getFavoriteColleagues();
      expect(list.length, equals(1));
      expect(list.first.id, equals('u-idempotent-1'));
      expect(list.first.isFavorite, isTrue); // Ensures favorite flag is enforced
    });

    test('addFavoriteColleague updates existing colleague with newer metadata without duplicating', () async {
      const initial = Colleague(id: 'u-1', name: 'Ada Lovelace', email: 'ada@computing.org');
      await storage.addFavoriteColleague(initial);

      // Same ID, updated desk name and room name
      const updated = Colleague(
        id: 'u-1',
        name: 'Ada Lovelace Countess of Lovelace',
        email: 'ada@computing.org',
        deskName: 'DS-ANALYTICAL-01',
        roomName: 'Babbage Wing',
      );
      await storage.addFavoriteColleague(updated);

      final list = await storage.getFavoriteColleagues();
      expect(list.length, equals(1));
      expect(list.first.name, equals('Ada Lovelace Countess of Lovelace'));
      expect(list.first.deskName, equals('DS-ANALYTICAL-01'));
      expect(list.first.roomName, equals('Babbage Wing'));
      expect(list.first.isFavorite, isTrue);
    });

    test('removeFavoriteColleague is safe on non-existent IDs and empty lists', () async {
      // Removing from empty storage
      await storage.removeFavoriteColleague('non-existent-id');
      expect(await storage.getFavoriteColleagues(), isEmpty);

      // Populate with 2 items
      await storage.addFavoriteColleague(const Colleague(id: 'c1', name: 'User 1'));
      await storage.addFavoriteColleague(const Colleague(id: 'c2', name: 'User 2'));
      expect((await storage.getFavoriteColleagues()).length, equals(2));

      // Removing a non-existent ID leaves the 2 items intact
      await storage.removeFavoriteColleague('c999');
      final listAfterGhostRemove = await storage.getFavoriteColleagues();
      expect(listAfterGhostRemove.length, equals(2));

      // Removing c1 works
      await storage.removeFavoriteColleague('c1');
      final listAfterRemove = await storage.getFavoriteColleagues();
      expect(listAfterRemove.length, equals(1));
      expect(listAfterRemove.first.id, equals('c2'));

      // Repeating removal of c1 is safe and idempotent
      await storage.removeFavoriteColleague('c1');
      expect((await storage.getFavoriteColleagues()).length, equals(1));
    });

    test('Self-healing: adding or removing a favorite colleague recovers corrupted storage', () async {
      // Storage starts with completely corrupted JSON
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': 'CORRUPTED_BLOB{{{',
      });

      // Calling addFavoriteColleague should recover cleanly and save the valid colleague
      const colleague = Colleague(id: 'heal-1', name: 'Florence Nightingale');
      await storage.addFavoriteColleague(colleague);

      final list = await storage.getFavoriteColleagues();
      expect(list.length, equals(1));
      expect(list.first.name, equals('Florence Nightingale'));
      expect(list.first.isFavorite, isTrue);

      // Verify the raw SharedPreferences string is now valid JSON array
      final prefs = await SharedPreferences.getInstance();
      final rawJson = prefs.getString('favorite_colleagues');
      expect(rawJson, isNotNull);
      final decoded = jsonDecode(rawJson!);
      expect(decoded, isA<List>());
      expect((decoded as List).length, equals(1));
    });

    test('isFavoriteColleague reports correctly and does not crash on corrupted storage', () async {
      SharedPreferences.setMockInitialValues({
        'favorite_colleagues': 'MALFORMED',
      });
      expect(await storage.isFavoriteColleague('any-id'), isFalse);

      await storage.addFavoriteColleague(const Colleague(id: 'fav-1', name: 'Alan Turing'));
      expect(await storage.isFavoriteColleague('fav-1'), isTrue);
      expect(await storage.isFavoriteColleague('fav-2'), isFalse);
    });
  });
}
