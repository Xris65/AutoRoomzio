import 'package:auto_roomzio/holiday_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('HolidayService', () {
    group('Constants & supportedCountries', () {
      test('exposes expected country codes and labels', () {
        expect(HolidayService.countryFrance, 'FR');
        expect(HolidayService.countrySwitzerland, 'CH');
        expect(HolidayService.countryBelgium, 'BE');
        expect(HolidayService.supportedCountries, {
          'FR': 'France',
          'CH': 'Suisse',
          'BE': 'Belgique',
        });
      });
    });

    group('computeEasterSunday', () {
      test('computes Easter Sunday accurately for 2025, 2026 and 2027 in UTC', () {
        final easter2025 = HolidayService.computeEasterSunday(2025);
        expect(easter2025, DateTime.utc(2025, 4, 20));
        expect(easter2025.isUtc, isTrue);

        final easter2026 = HolidayService.computeEasterSunday(2026);
        expect(easter2026, DateTime.utc(2026, 4, 5));
        expect(easter2026.isUtc, isTrue);

        final easter2027 = HolidayService.computeEasterSunday(2027);
        expect(easter2027, DateTime.utc(2027, 3, 28));
        expect(easter2027.isUtc, isTrue);
      });
    });

    group('getHolidaysForYear', () {
      final dateKeyPattern = RegExp(r'^\d{4}-\d{2}-\d{2}$');

      test('returns exact FR holidays (11) for 2025, 2026 and 2027', () {
        final expectedByYear = <int, Map<String, String>>{
          2025: {
            '2025-01-01': 'Jour de l\'An',
            '2025-04-21': 'Lundi de Pâques',
            '2025-05-01': 'Fête du Travail',
            '2025-05-08': 'Victoire 1945',
            '2025-05-29': 'Jeudi de l\'Ascension',
            '2025-06-09': 'Lundi de Pentecôte',
            '2025-07-14': 'Fête Nationale',
            '2025-08-15': 'Assomption',
            '2025-11-01': 'Toussaint',
            '2025-11-11': 'Armistice 1918',
            '2025-12-25': 'Noël',
          },
          2026: {
            '2026-01-01': 'Jour de l\'An',
            '2026-04-06': 'Lundi de Pâques',
            '2026-05-01': 'Fête du Travail',
            '2026-05-08': 'Victoire 1945',
            '2026-05-14': 'Jeudi de l\'Ascension',
            '2026-05-25': 'Lundi de Pentecôte',
            '2026-07-14': 'Fête Nationale',
            '2026-08-15': 'Assomption',
            '2026-11-01': 'Toussaint',
            '2026-11-11': 'Armistice 1918',
            '2026-12-25': 'Noël',
          },
          2027: {
            '2027-01-01': 'Jour de l\'An',
            '2027-03-29': 'Lundi de Pâques',
            '2027-05-01': 'Fête du Travail',
            '2027-05-06': 'Jeudi de l\'Ascension',
            '2027-05-08': 'Victoire 1945',
            '2027-05-17': 'Lundi de Pentecôte',
            '2027-07-14': 'Fête Nationale',
            '2027-08-15': 'Assomption',
            '2027-11-01': 'Toussaint',
            '2027-11-11': 'Armistice 1918',
            '2027-12-25': 'Noël',
          },
        };

        for (final entry in expectedByYear.entries) {
          final holidays = HolidayService.getHolidaysForYear(
            entry.key,
            countryCode: HolidayService.countryFrance,
          );
          expect(holidays.length, 11);
          expect(holidays.keys.every(dateKeyPattern.hasMatch), isTrue);
          expect(holidays, entry.value);
          expect(
            holidays.keys.toList(),
            equals(holidays.keys.toList()..sort()),
          );
        }
      });

      test('returns exact CH holidays (9) for 2025, 2026 and 2027', () {
        final expectedByYear = <int, Map<String, String>>{
          2025: {
            '2025-01-01': 'Jour de l\'An',
            '2025-01-02': 'Saint-Berchtold',
            '2025-04-18': 'Vendredi saint',
            '2025-04-21': 'Lundi de Pâques',
            '2025-05-29': 'Jeudi de l\'Ascension',
            '2025-06-09': 'Lundi de Pentecôte',
            '2025-08-01': 'Fête Nationale Suisse',
            '2025-12-25': 'Noël',
            '2025-12-26': 'Saint-Étienne',
          },
          2026: {
            '2026-01-01': 'Jour de l\'An',
            '2026-01-02': 'Saint-Berchtold',
            '2026-04-03': 'Vendredi saint',
            '2026-04-06': 'Lundi de Pâques',
            '2026-05-14': 'Jeudi de l\'Ascension',
            '2026-05-25': 'Lundi de Pentecôte',
            '2026-08-01': 'Fête Nationale Suisse',
            '2026-12-25': 'Noël',
            '2026-12-26': 'Saint-Étienne',
          },
          2027: {
            '2027-01-01': 'Jour de l\'An',
            '2027-01-02': 'Saint-Berchtold',
            '2027-03-26': 'Vendredi saint',
            '2027-03-29': 'Lundi de Pâques',
            '2027-05-06': 'Jeudi de l\'Ascension',
            '2027-05-17': 'Lundi de Pentecôte',
            '2027-08-01': 'Fête Nationale Suisse',
            '2027-12-25': 'Noël',
            '2027-12-26': 'Saint-Étienne',
          },
        };

        for (final entry in expectedByYear.entries) {
          final holidays = HolidayService.getHolidaysForYear(
            entry.key,
            countryCode: HolidayService.countrySwitzerland,
          );
          expect(holidays.length, 9);
          expect(holidays.keys.every(dateKeyPattern.hasMatch), isTrue);
          expect(holidays, entry.value);
          expect(
            holidays.keys.toList(),
            equals(holidays.keys.toList()..sort()),
          );
        }
      });

      test('returns exact BE holidays (10) for 2025, 2026 and 2027', () {
        final expectedByYear = <int, Map<String, String>>{
          2025: {
            '2025-01-01': 'Jour de l\'An',
            '2025-04-21': 'Lundi de Pâques',
            '2025-05-01': 'Fête du Travail',
            '2025-05-29': 'Jeudi de l\'Ascension',
            '2025-06-09': 'Lundi de Pentecôte',
            '2025-07-21': 'Fête Nationale Belge',
            '2025-08-15': 'Assomption',
            '2025-11-01': 'Toussaint',
            '2025-11-11': 'Armistice',
            '2025-12-25': 'Noël',
          },
          2026: {
            '2026-01-01': 'Jour de l\'An',
            '2026-04-06': 'Lundi de Pâques',
            '2026-05-01': 'Fête du Travail',
            '2026-05-14': 'Jeudi de l\'Ascension',
            '2026-05-25': 'Lundi de Pentecôte',
            '2026-07-21': 'Fête Nationale Belge',
            '2026-08-15': 'Assomption',
            '2026-11-01': 'Toussaint',
            '2026-11-11': 'Armistice',
            '2026-12-25': 'Noël',
          },
          2027: {
            '2027-01-01': 'Jour de l\'An',
            '2027-03-29': 'Lundi de Pâques',
            '2027-05-01': 'Fête du Travail',
            '2027-05-06': 'Jeudi de l\'Ascension',
            '2027-05-17': 'Lundi de Pentecôte',
            '2027-07-21': 'Fête Nationale Belge',
            '2027-08-15': 'Assomption',
            '2027-11-01': 'Toussaint',
            '2027-11-11': 'Armistice',
            '2027-12-25': 'Noël',
          },
        };

        for (final entry in expectedByYear.entries) {
          final holidays = HolidayService.getHolidaysForYear(
            entry.key,
            countryCode: HolidayService.countryBelgium,
          );
          expect(holidays.length, 10);
          expect(holidays.keys.every(dateKeyPattern.hasMatch), isTrue);
          expect(holidays, entry.value);
          expect(
            holidays.keys.toList(),
            equals(holidays.keys.toList()..sort()),
          );
        }
      });
    });

    group('isHoliday & getHolidayName', () {
      test('checks fixed and mobile holidays across FR, CH and BE', () {
        // France defaults & specifics
        expect(HolidayService.isHoliday(DateTime(2025, 7, 14)), isTrue);
        expect(HolidayService.getHolidayName(DateTime(2025, 7, 14)), 'Fête Nationale');
        expect(HolidayService.getHolidayName(DateTime(2026, 5, 8), countryCode: 'FR'), 'Victoire 1945');
        expect(HolidayService.getHolidayName(DateTime(2027, 11, 11), countryCode: 'FR'), 'Armistice 1918');
        expect(HolidayService.isHoliday(DateTime(2025, 4, 18), countryCode: 'FR'), isFalse);

        // Suisse specifics
        expect(HolidayService.getHolidayName(DateTime(2025, 1, 2), countryCode: 'CH'), 'Saint-Berchtold');
        expect(HolidayService.getHolidayName(DateTime(2025, 4, 18), countryCode: 'CH'), 'Vendredi saint');
        expect(HolidayService.getHolidayName(DateTime(2026, 4, 3), countryCode: 'CH'), 'Vendredi saint');
        expect(HolidayService.getHolidayName(DateTime(2027, 3, 26), countryCode: 'CH'), 'Vendredi saint');
        expect(HolidayService.getHolidayName(DateTime(2026, 8, 1), countryCode: 'CH'), 'Fête Nationale Suisse');
        expect(HolidayService.getHolidayName(DateTime(2027, 12, 26), countryCode: 'CH'), 'Saint-Étienne');
        expect(HolidayService.isHoliday(DateTime(2025, 5, 1), countryCode: 'CH'), isFalse);
        expect(HolidayService.isHoliday(DateTime(2025, 7, 14), countryCode: 'CH'), isFalse);

        // Belgique specifics
        expect(HolidayService.getHolidayName(DateTime(2025, 7, 21), countryCode: 'BE'), 'Fête Nationale Belge');
        expect(HolidayService.getHolidayName(DateTime(2026, 11, 11), countryCode: 'BE'), 'Armistice');
        expect(HolidayService.isHoliday(DateTime(2025, 5, 8), countryCode: 'BE'), isFalse);
        expect(HolidayService.isHoliday(DateTime(2025, 4, 18), countryCode: 'BE'), isFalse);
      });

      test('returns false and null for regular working days', () {
        final regularDays = [
          DateTime(2025, 2, 12),
          DateTime(2025, 4, 17),
          DateTime(2025, 6, 10),
          DateTime(2026, 3, 18),
          DateTime(2026, 9, 22),
          DateTime(2027, 10, 14),
        ];

        for (final date in regularDays) {
          for (final country in ['FR', 'CH', 'BE']) {
            expect(HolidayService.isHoliday(date, countryCode: country), isFalse);
            expect(HolidayService.getHolidayName(date, countryCode: country), isNull);
          }
        }
      });

      test('handles local vs UTC DateTimes and DST boundaries without day shift', () {
        // 2027-03-28 is Easter Sunday AND the European DST spring-forward date.
        // 2027-03-29 (Lundi de Pâques) must resolve identically across local & UTC times.
        final localMidnight = DateTime(2027, 3, 29, 0, 0, 0);
        final localLateNight = DateTime(2027, 3, 29, 23, 59, 59, 999);
        final utcEarlyMorning = DateTime.utc(2027, 3, 29, 0, 15, 0);
        final utcLateNight = DateTime.utc(2027, 3, 29, 23, 45, 0);

        for (final date in [
          localMidnight,
          localLateNight,
          utcEarlyMorning,
          utcLateNight,
        ]) {
          expect(HolidayService.isHoliday(date, countryCode: 'FR'), isTrue);
          expect(
            HolidayService.getHolidayName(date, countryCode: 'FR'),
            'Lundi de Pâques',
          );
          expect(
            HolidayService.getHolidayName(date, countryCode: 'CH'),
            'Lundi de Pâques',
          );
          expect(
            HolidayService.getHolidayName(date, countryCode: 'BE'),
            'Lundi de Pâques',
          );
        }

        // Easter Sunday itself is not a holiday in FR/CH/BE (only Monday is, plus Good Friday in CH)
        expect(HolidayService.isHoliday(DateTime(2027, 3, 28, 2, 30), countryCode: 'FR'), isFalse);
        expect(HolidayService.isHoliday(DateTime.utc(2027, 3, 28, 23, 59), countryCode: 'CH'), isFalse);

        // Autumn DST fall-back boundary (2025-10-26) followed by Toussaint (2025-11-01)
        expect(HolidayService.isHoliday(DateTime(2025, 10, 26, 23, 59), countryCode: 'FR'), isFalse);
        expect(HolidayService.getHolidayName(DateTime(2025, 11, 1, 0, 1), countryCode: 'FR'), 'Toussaint');
        expect(HolidayService.getHolidayName(DateTime.utc(2025, 11, 1, 23, 59), countryCode: 'BE'), 'Toussaint');
      });

      test('handles case-insensitive countryCode and falls back cleanly to FR on unknown code', () {
        expect(HolidayService.getHolidayName(DateTime(2025, 1, 2), countryCode: 'ch'), 'Saint-Berchtold');
        expect(HolidayService.getHolidayName(DateTime(2025, 7, 21), countryCode: ' be '), 'Fête Nationale Belge');
        expect(HolidayService.getHolidayName(DateTime(2025, 7, 14), countryCode: 'fr'), 'Fête Nationale');

        // Unknown codes fallback cleanly to FR
        expect(HolidayService.getHolidayName(DateTime(2025, 7, 14), countryCode: 'DE'), 'Fête Nationale');
        expect(HolidayService.isHoliday(DateTime(2025, 5, 8), countryCode: 'UNKNOWN'), isTrue);
        expect(HolidayService.isHoliday(DateTime(2025, 1, 2), countryCode: 'US'), isFalse);
        expect(HolidayService.getHolidaysForYear(2025, countryCode: '').length, 11);
      });
    });
  });
}
