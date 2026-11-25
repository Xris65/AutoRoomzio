/// Utilitaires centralisés pour le formatage et l'arithmétique calendaire anti-DST.
const List<String> frenchWeekdays = <String>[
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

const List<String> frenchShortWeekdays = <String>[
  'Lun',
  'Mar',
  'Mer',
  'Jeu',
  'Ven',
  'Sam',
  'Dim',
];

const List<String> _frenchShortMonths = <String>[
  'janv.',
  'févr.',
  'mars',
  'avr.',
  'mai',
  'juin',
  'juil.',
  'août',
  'sept.',
  'oct.',
  'nov.',
  'déc.',
];

/// Normalise une date en minuit local (année, mois, jour) sans composante horaire.
DateTime normalizeLocalDate(DateTime d) => DateTime(d.year, d.month, d.day);

/// Ajoute [days] jours calendaires sans dérive liée aux changements d'heure (DST 23h/25h).
DateTime addCalendarDays(DateTime d, int days) {
  final u = DateTime.utc(d.year, d.month, d.day + days);
  return DateTime(u.year, u.month, u.day);
}

/// Calcule l'écart exact en jours calendaires entre [from] et [to] en UTC (insensible au DST).
int calendarDaysBetween(DateTime from, DateTime to) =>
    DateTime.utc(to.year, to.month, to.day)
        .difference(DateTime.utc(from.year, from.month, from.day))
        .inDays;

String formatIsoDate(DateTime date) => DateHelpers.formatIsoDate(date);

String formatFrenchDate(DateTime date, {bool includeYear = false}) =>
    DateHelpers.formatFrenchDate(date, includeYear: includeYear);

class DateHelpers {
  static const List<String> frenchWeekdaysList = frenchWeekdays;
  static const List<String> frenchShortWeekdaysList = frenchShortWeekdays;

  static const Map<int, String> frenchWeekdaysMap = <int, String>{
    1: 'Lundi',
    2: 'Mardi',
    3: 'Mercredi',
    4: 'Jeudi',
    5: 'Vendredi',
    6: 'Samedi',
    7: 'Dimanche',
  };

  static const Map<int, String> frenchShortWeekdaysMap = <int, String>{
    1: 'Lun',
    2: 'Mar',
    3: 'Mer',
    4: 'Jeu',
    5: 'Ven',
    6: 'Sam',
    7: 'Dim',
  };

  static DateTime normalizeLocalDate(DateTime d) =>
      DateTime(d.year, d.month, d.day);

  static DateTime addCalendarDays(DateTime d, int days) {
    final u = DateTime.utc(d.year, d.month, d.day + days);
    return DateTime(u.year, u.month, u.day);
  }

  static int calendarDaysBetween(DateTime from, DateTime to) =>
      DateTime.utc(to.year, to.month, to.day)
          .difference(DateTime.utc(from.year, from.month, from.day))
          .inDays;

  static String formatIsoDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static String formatShortDay(DateTime d) {
    final name = frenchShortWeekdays[d.weekday - 1];
    return '$name ${d.day}';
  }

  static String formatFrenchDate(DateTime date, {bool includeYear = false}) {
    final now = DateTime.now();
    final diff = calendarDaysBetween(now, date);

    final weekday = frenchWeekdays[date.weekday - 1];
    final month = _frenchShortMonths[date.month - 1];
    final yearSuffix = includeYear ? ' ${date.year}' : '';

    if (diff == 0) return "Aujourd'hui (${date.day} $month$yearSuffix)";
    if (diff == 1) return "Demain (${date.day} $month$yearSuffix)";
    if (diff == -1) return "Hier (${date.day} $month$yearSuffix)";
    return "$weekday ${date.day} $month$yearSuffix";
  }

  static bool isSameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;
}
