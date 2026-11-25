import 'package:auto_roomzio/utils/date_helpers.dart';
import 'package:auto_roomzio/utils/workspace_helpers.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('addCalendarDays / calendarDaysBetween (DST-safe)', () {
    // 30/03/2025 (spring forward) and 26/10/2025 (fall back) in Europe/Paris.
    // The invariant must hold whatever the host time zone is.
    final List<DateTime> dstDays = <DateTime>[
      DateTime(2025, 3, 30),
      DateTime(2025, 10, 26),
    ];

    for (final DateTime day in dstDays) {
      test('crossing ${formatIsoDate(day)} keeps calendar invariants', () {
        final DateTime before = addCalendarDays(day, -1);
        final DateTime after = addCalendarDays(day, 1);

        expect(before, DateTime(day.year, day.month, day.day - 1));
        expect(after, DateTime(day.year, day.month, day.day + 1));
        expect(after.hour, 0);
        expect(after.minute, 0);
        expect(calendarDaysBetween(before, after), 2);
        expect(calendarDaysBetween(after, before), -2);
        expect(calendarDaysBetween(day, addCalendarDays(day, 7)), 7);
      });
    }

    test('ignores time-of-day components', () {
      final DateTime lateEvening = DateTime(2025, 10, 25, 23, 59);
      final DateTime earlyMorning = DateTime(2025, 10, 27, 0, 1);
      expect(calendarDaysBetween(lateEvening, earlyMorning), 2);
      expect(addCalendarDays(lateEvening, 1), DateTime(2025, 10, 26));
      expect(normalizeLocalDate(lateEvening), DateTime(2025, 10, 25));
    });

    test('rolls over month and year boundaries', () {
      expect(addCalendarDays(DateTime(2025, 12, 31), 1), DateTime(2026, 1, 1));
      expect(addCalendarDays(DateTime(2024, 3, 1), -1), DateTime(2024, 2, 29));
      expect(
        calendarDaysBetween(DateTime(2025, 1, 1), DateTime(2026, 1, 1)),
        365,
      );
    });
  });

  group('extractRoomName', () {
    test('"Open Space - 04" yields the room prefix (trim: true)', () {
      expect(
        extractRoomName(<String, dynamic>{'name': 'Open Space - 04'}),
        'Open Space',
      );
    });

    test('"Open Space - 04" yields the room prefix (trim: false)', () {
      expect(
        extractRoomName(
          <String, dynamic>{'name': 'Open Space - 04'},
          trim: false,
        ),
        'Open Space',
      );
    });

    test('explicit roomName wins over parsed name', () {
      expect(
        extractRoomName(<String, dynamic>{
          'roomName': ' Salle A ',
          'name': 'Open Space - 04',
        }),
        'Salle A',
      );
    });
  });

  group('isBookableWorkspace', () {
    test('excludes Parking and PhoneBooth types', () {
      expect(
        isBookableWorkspace(<String, dynamic>{'workspaceType': 'Parking'}),
        isFalse,
      );
      expect(
        isBookableWorkspace(<String, dynamic>{'type': 'PhoneBooth'}),
        isFalse,
      );
      expect(
        isBookableWorkspace(<String, dynamic>{
          'workspaceType': 'Parking',
          'isBookable': true,
        }),
        isFalse,
      );
    });

    test('respects explicit false flags', () {
      expect(
        isBookableWorkspace(<String, dynamic>{
          'workspaceType': 'Desk',
          'isBookable': false,
        }),
        isFalse,
      );
      expect(
        isBookableWorkspace(<String, dynamic>{
          'type': 1,
          'isReservable': false,
        }),
        isFalse,
      );
    });

    test('accepts desks', () {
      expect(
        isBookableWorkspace(<String, dynamic>{'workspaceType': 'Desk'}),
        isTrue,
      );
      expect(isBookableWorkspace(<String, dynamic>{'type': 1}), isTrue);
    });
  });
}
