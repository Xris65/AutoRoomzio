import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:auto_roomzio/models/desk_occupant.dart';
import 'package:auto_roomzio/api_service.dart';
import 'package:auto_roomzio/widgets/occupant_details_sheet.dart';

void main() {
  group('Delegation Ownership Tests (Bug #1 Fix)', () {
    // ═════════════════════════════════════════════════════════════════════════
    // 1. DeskOccupant Domain Model Distinction
    // ═════════════════════════════════════════════════════════════════════════
    group('1. DeskOccupant model delegation classification', () {
      test('Reservation by me for colleague sets isDelegatedByMe == true', () {
        const occ = DeskOccupant(
          workspaceId: 'ws-101',
          occupantName: 'Bob Dylan',
          occupantId: 'usr-bob',
          occupantEmail: 'bob@corp.com',
          isMe: false,
          isDelegatedByMe: true,
          bookedByName: 'Alice',
        );

        expect(occ.isDelegatedByMe, isTrue);
        expect(occ.isDelegated, isTrue);
        expect(occ.isDelegatedForMe, isFalse);
        expect(occ.isDelegatedOther, isFalse);
        expect(occ.isMe, isFalse);
      });

      test('Reservation by Alice for Bob sets isDelegatedByMe == false and isDelegatedOther == true', () {
        const occ = DeskOccupant(
          workspaceId: 'ws-102',
          occupantName: 'Bob Dylan',
          occupantId: 'usr-bob',
          occupantEmail: 'bob@corp.com',
          isMe: false,
          isDelegated: true,
          isDelegatedByMe: false,
          isDelegatedForMe: false,
          bookedByName: 'Alice Wonder',
        );

        expect(occ.isDelegatedByMe, isFalse);
        expect(occ.isDelegated, isTrue);
        expect(occ.isDelegatedOther, isTrue);
        expect(occ.isDelegatedForMe, isFalse);
        expect(occ.isMe, isFalse);
      });

      test('Reservation by Alice for me sets isDelegatedForMe == true and isMe == true', () {
        const occ = DeskOccupant(
          workspaceId: 'ws-103',
          occupantName: 'Myself',
          occupantId: 'usr-me',
          occupantEmail: 'me@corp.com',
          isMe: true,
          isDelegated: true,
          isDelegatedByMe: false,
          isDelegatedForMe: true,
          bookedByName: 'Alice Wonder',
        );

        expect(occ.isDelegatedByMe, isFalse);
        expect(occ.isDelegatedForMe, isTrue);
        expect(occ.isDelegatedOther, isFalse);
        expect(occ.isMe, isTrue);
      });

      test('Serialization roundtrip preserves delegation flags', () {
        const occ = DeskOccupant(
          workspaceId: 'ws-104',
          occupantName: 'Bob Dylan',
          isDelegatedByMe: true,
          bookedByName: 'My Self',
        );

        final json = occ.toJson();
        expect(json['isDelegatedByMe'], isTrue);
        expect(json['isDelegated'], isTrue);

        final deserialized = DeskOccupant.fromJson(json);
        expect(deserialized.isDelegatedByMe, isTrue);
        expect(deserialized.isDelegated, isTrue);
        expect(deserialized.isDelegatedOther, isFalse);
      });
    });

    // ═════════════════════════════════════════════════════════════════════════
    // 2. RoomzApiService.getFloorOccupants Ownership Resolution
    // ═════════════════════════════════════════════════════════════════════════
    group('2. RoomzApiService.getFloorOccupants delegation ownership resolution', () {
      test('Correctly identifies isDelegatedByMe vs isDelegatedOther from API response', () async {
        final mockResponse = {
          "data": [
            // Desk 1: Me booked for Bob -> isDelegatedByMe == true
            {
              "workspaceId": "ws-by-me",
              "status": "Reserved",
              "bookedTimeSlot": {
                "eventId": "evt-1",
                "creator": {"id": "usr-me", "name": "Myself", "email": "me@corp.com"},
                "bookedFor": {"id": "usr-bob", "name": "Bob Dylan", "email": "bob@corp.com"},
              }
            },
            // Desk 2: Alice booked for Bob -> isDelegatedOther == true, isDelegatedByMe == false
            {
              "workspaceId": "ws-by-alice",
              "status": "Reserved",
              "bookedTimeSlot": {
                "eventId": "evt-2",
                "creator": {"id": "usr-alice", "name": "Alice Wonder", "email": "alice@corp.com"},
                "bookedFor": {"id": "usr-bob", "name": "Bob Dylan", "email": "bob@corp.com"},
              }
            },
            // Desk 3: Alice booked for Me -> isDelegatedForMe == true, isMe == true
            {
              "workspaceId": "ws-for-me",
              "status": "Reserved",
              "bookedTimeSlot": {
                "eventId": "evt-3",
                "creator": {"id": "usr-alice", "name": "Alice Wonder", "email": "alice@corp.com"},
                "bookedFor": {"id": "usr-me", "name": "Myself", "email": "me@corp.com"},
              }
            },
          ]
        };

        final client = MockClient((req) async {
          if (req.url.path.contains('/workspaces/calendars')) {
            return http.Response(jsonEncode(mockResponse), 200);
          }
          return http.Response('Not found', 404);
        });

        final api = RoomzApiService(client: client);
        final occupants = await api.getFloorOccupants(
          'mock-token',
          'floor-1',
          '2026-10-15',
          myUserId: 'usr-me',
          myUserEmail: 'me@corp.com',
        );

        // a) Desk reserved by me for colleague Bob
        final occByMe = occupants['ws-by-me']!;
        expect(occByMe.occupantName, equals('Bob Dylan'));
        expect(occByMe.isDelegated, isTrue);
        expect(occByMe.isDelegatedByMe, isTrue, reason: 'Must be true because creatorId == usr-me');
        expect(occByMe.isDelegatedOther, isFalse);
        expect(occByMe.isMe, isFalse);

        // b) Desk reserved by Alice for Bob
        final occByAlice = occupants['ws-by-alice']!;
        expect(occByAlice.occupantName, equals('Bob Dylan'));
        expect(occByAlice.isDelegated, isTrue);
        expect(occByAlice.isDelegatedByMe, isFalse, reason: 'Must be false because creator is Alice, not current user');
        expect(occByAlice.isDelegatedOther, isTrue);
        expect(occByAlice.bookedByName, equals('Alice Wonder'));
        expect(occByAlice.isMe, isFalse);

        // c) Desk reserved by Alice for Me
        final occForMe = occupants['ws-for-me']!;
        expect(occForMe.occupantName, equals('Myself'));
        expect(occForMe.isDelegated, isTrue);
        expect(occForMe.isDelegatedByMe, isFalse);
        expect(occForMe.isDelegatedForMe, isTrue);
        expect(occForMe.isMe, isTrue);
      });

      test('StorageService delegatedBookingsMap confers isDelegatedByMe == true', () async {
        final mockResponse = {
          "data": [
            {
              "workspaceId": "ws-local-del",
              "status": "Reserved",
              "bookedTimeSlot": {
                "eventId": "evt-local",
                "creator": {"name": "Roomz"},
                "bookedFor": {"name": "Bob Dylan"},
              }
            }
          ]
        };

        final client = MockClient((req) async => http.Response(jsonEncode(mockResponse), 200));
        final api = RoomzApiService(client: client);

        final occupants = await api.getFloorOccupants(
          'mock-token',
          'floor-1',
          '2026-10-15',
          myUserId: 'usr-me',
          delegatedBookingsMap: {'2026-10-15#ws-local-del': 'ws-local-del|Bob Dylan|Bureau 1|evt-local'},
        );

        final occ = occupants['ws-local-del']!;
        expect(occ.isDelegatedByMe, isTrue);
      });
    });

    // ═════════════════════════════════════════════════════════════════════════
    // 3. OccupantDetailsSheet UI & Button Display
    // ═════════════════════════════════════════════════════════════════════════
    group('3. OccupantDetailsSheet UI & cancellation button visibility', () {
      testWidgets('Case a: Reservation by me for Bob -> displays "Réservé par vous" and shows "Libérer la place du collègue"', (tester) async {
        bool cancelDelegationCalled = false;

        const occupant = DeskOccupant(
          workspaceId: 'ws-101',
          occupantName: 'Bob Dylan',
          occupantEmail: 'bob@corp.com',
          isMe: false,
          isDelegated: true,
          isDelegatedByMe: true,
          bookedByName: 'Myself',
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  OccupantDetailsSheet.show(
                    context: ctx,
                    workspace: {'id': 'ws-101', 'name': 'Bureau 101', 'roomName': 'Open Space'},
                    occupant: occupant,
                    onCancelDelegatedBooking: () => cancelDelegationCalled = true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Label verification: "Réservé par vous"
        expect(find.text('Réservé par vous'), findsOneWidget);

        // Action button verification: "Libérer la place du collègue" is present and functional
        final cancelButton = find.text('Libérer la place du collègue');
        expect(cancelButton, findsOneWidget);

        await tester.tap(cancelButton);
        await tester.pumpAndSettle();
        expect(cancelDelegationCalled, isTrue);
      });

      testWidgets('Case b: Reservation by Alice for Bob -> displays "Réservé pour Bob par Alice" and hides cancel button (no 403 error)', (tester) async {
        bool unexpectedCancelCalled = false;

        const occupant = DeskOccupant(
          workspaceId: 'ws-102',
          occupantName: 'Bob',
          occupantEmail: 'bob@corp.com',
          isMe: false,
          isDelegated: true,
          isDelegatedByMe: false,
          isDelegatedOther: true,
          bookedByName: 'Alice',
        );

        await tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (ctx) => ElevatedButton(
                onPressed: () {
                  OccupantDetailsSheet.show(
                    context: ctx,
                    workspace: {'id': 'ws-102', 'name': 'Bureau 102', 'roomName': 'Zone Calme'},
                    occupant: occupant,
                    // Even if a callback were passed by mistake, sheet must protect and hide it
                    onCancelDelegatedBooking: () => unexpectedCancelCalled = true,
                  );
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ));

        await tester.tap(find.text('Open'));
        await tester.pumpAndSettle();

        // Label verification: "Réservé pour Bob par Alice"
        expect(find.text('Réservé pour Bob par Alice'), findsOneWidget);

        // Verification: NO button to cancel colleague's booking is presented to the user
        expect(find.text('Libérer la place du collègue'), findsNothing);
        expect(find.text('Libérer ma place'), findsNothing);
        expect(unexpectedCancelCalled, isFalse);
      });
    });
  });
}
