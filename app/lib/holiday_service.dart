import 'utils/date_helpers.dart';

/// Service de calcul des jours fériés officiels pour la France, la Suisse et la Belgique.
class HolidayService {
  static const String countryFrance = 'FR';
  static const String countrySwitzerland = 'CH';
  static const String countryBelgium = 'BE';

  static final Map<String, Map<String, String>> _holidaysCache = {};

  static const Map<String, String> supportedCountries = {
    'FR': 'France',
    'CH': 'Suisse',
    'BE': 'Belgique',
  };

  /// Calcule le dimanche de Pâques pour l'année [year] (algorithme de Meeus/Butcher).
  static DateTime computeEasterSunday(int year) {
    final int a = year % 19;
    final int b = year ~/ 100;
    final int c = year % 100;
    final int d = b ~/ 4;
    final int e = b % 4;
    final int f = (b + 8) ~/ 25;
    final int g = (b - f + 1) ~/ 3;
    final int h = (19 * a + b - d - g + 15) % 30;
    final int i = c ~/ 4;
    final int k = c % 4;
    final int l = (32 + 2 * e + 2 * i - h - k) % 7;
    final int m = (a + 11 * h + 22 * l) ~/ 451;
    final int month = (h + l - 7 * m + 114) ~/ 31;
    final int day = ((h + l - 7 * m + 114) % 31) + 1;

    return DateTime.utc(year, month, day);
  }

  /// Retourne le nom du jour férié en français si [date] est un jour férié
  /// officiel dans le pays [countryCode] ('FR', 'CH', 'BE'), ou `null` sinon.
  ///
  /// La comparaison normalise la date en `DateTime.utc(date.year, date.month, date.day)`
  /// pour éviter tout écart lié à l'heure ou au changement d'heure (DST).
  /// Un [countryCode] inconnu bascule sur [countryFrance] (`'FR'`).
  static String? getHolidayName(
    DateTime date, {
    String countryCode = countryFrance,
  }) {
    final normalizedDate = DateTime.utc(date.year, date.month, date.day);
    final holidays = getHolidaysForYear(
      normalizedDate.year,
      countryCode: countryCode,
    );
    return holidays[DateHelpers.formatIsoDate(normalizedDate)];
  }

  /// Retourne `true` si [date] est un jour férié dans [countryCode].
  ///
  /// Un [countryCode] inconnu bascule sur [countryFrance] (`'FR'`).
  static bool isHoliday(
    DateTime date, {
    String countryCode = countryFrance,
  }) {
    return getHolidayName(date, countryCode: countryCode) != null;
  }

  /// Retourne la map `{ 'YYYY-MM-DD': 'Nom du jour férié' }` de tous les jours
  /// fériés de l'année [year] pour [countryCode].
  ///
  /// Les entrées sont triées par ordre chronologique. Un [countryCode] est
  /// accepté de manière insensible à la casse ; s'il est inconnu, la méthode
  /// bascule proprement sur [countryFrance] (`'FR'`).
  static Map<String, String> getHolidaysForYear(
    int year, {
    String countryCode = countryFrance,
  }) {
    final normalizedCountry = _normalizeCountryCode(countryCode);
    final cacheKey = '${year}_$normalizedCountry';
    final cached = _holidaysCache[cacheKey];
    if (cached != null) {
      return cached;
    }

    final easter = computeEasterSunday(year);

    final holidays = <DateTime, String>{
      DateTime.utc(year, 1, 1): 'Jour de l\'An',
      easter.add(const Duration(days: 1)): 'Lundi de Pâques',
      easter.add(const Duration(days: 39)): 'Jeudi de l\'Ascension',
      easter.add(const Duration(days: 50)): 'Lundi de Pentecôte',
      DateTime.utc(year, 12, 25): 'Noël',
    };

    switch (normalizedCountry) {
      case countrySwitzerland:
        holidays[DateTime.utc(year, 1, 2)] = 'Saint-Berchtold';
        holidays[easter.add(const Duration(days: -2))] = 'Vendredi saint';
        holidays[DateTime.utc(year, 8, 1)] = 'Fête Nationale Suisse';
        holidays[DateTime.utc(year, 12, 26)] = 'Saint-Étienne';
      case countryBelgium:
        holidays[DateTime.utc(year, 5, 1)] = 'Fête du Travail';
        holidays[DateTime.utc(year, 7, 21)] = 'Fête Nationale Belge';
        holidays[DateTime.utc(year, 8, 15)] = 'Assomption';
        holidays[DateTime.utc(year, 11, 1)] = 'Toussaint';
        holidays[DateTime.utc(year, 11, 11)] = 'Armistice';
      case countryFrance:
      default:
        holidays[DateTime.utc(year, 5, 1)] = 'Fête du Travail';
        holidays[DateTime.utc(year, 5, 8)] = 'Victoire 1945';
        holidays[DateTime.utc(year, 7, 14)] = 'Fête Nationale';
        holidays[DateTime.utc(year, 8, 15)] = 'Assomption';
        holidays[DateTime.utc(year, 11, 1)] = 'Toussaint';
        holidays[DateTime.utc(year, 11, 11)] = 'Armistice 1918';
    }

    final sortedEntries = holidays.entries.toList()
      ..sort((a, b) => a.key.compareTo(b.key));

    final result = Map<String, String>.unmodifiable({
      for (final entry in sortedEntries)
        DateHelpers.formatIsoDate(entry.key): entry.value,
    });
    _holidaysCache[cacheKey] = result;
    return result;
  }

  static String _normalizeCountryCode(String countryCode) {
    final normalized = countryCode.trim().toUpperCase();
    if (supportedCountries.containsKey(normalized)) {
      return normalized;
    }
    return countryFrance;
  }
}
