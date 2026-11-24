/// Utilitaires centralisés pour le formatage et la comparaison de dates.
const List<String> frenchWeekdays = [
  'Lundi',
  'Mardi',
  'Mercredi',
  'Jeudi',
  'Vendredi',
  'Samedi',
  'Dimanche',
];

const List<String> frenchShortWeekdays = [
  'Lun',
  'Mar',
  'Mer',
  'Jeu',
  'Ven',
  'Sam',
  'Dim',
];

const List<String> _frenchShortMonths = [
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

String formatIsoDate(DateTime date) => DateHelpers.formatIsoDate(date);

String formatFrenchDate(DateTime date, {bool includeYear = false}) =>
    DateHelpers.formatFrenchDate(date, includeYear: includeYear);

class DateHelpers {
  static const List<String> frenchWeekdaysList = frenchWeekdays;
  static const List<String> frenchShortWeekdaysList = frenchShortWeekdays;

  static const Map<int, String> frenchWeekdaysMap = {
    1: 'Lundi',
    2: 'Mardi',
    3: 'Mercredi',
    4: 'Jeudi',
    5: 'Vendredi',
    6: 'Samedi',
    7: 'Dimanche',
  };

  static const Map<int, String> frenchShortWeekdaysMap = {
    1: 'Lun',
    2: 'Mar',
    3: 'Mer',
    4: 'Jeu',
    5: 'Ven',
    6: 'Sam',
    7: 'Dim',
  };

  static String formatIsoDate(DateTime d) =>
      "${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}";

  static String formatShortDay(DateTime d) {
    final name = frenchShortWeekdays[d.weekday - 1];
    return '$name ${d.day}';
  }

  static String formatFrenchDate(DateTime date, {bool includeYear = false}) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final target = DateTime(date.year, date.month, date.day);
    final diff = target.difference(today).inDays;

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
