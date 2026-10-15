/// Helper class to format reservation display labels when a booking is delegated
/// (Milestone M2 / Bug #2: Display "Réservé pour [X] par [Y]").
class DelegationDisplayHelper {
  /// Formats the reservation label according to [creator] and [bookedFor].
  ///
  /// When `creator != null && bookedFor != null && creator != bookedFor`:
  /// - If [bookedFor] is "vous" or [isForMe] is true: `"Réservé par [Y] pour vous"`
  /// - If [creator] is "vous" or [isByMe] is true: `"Réservé pour [X] par vous"`
  /// - Otherwise: `"Réservé pour [X] par [Y]"`
  ///
  /// If creator and bookedFor are identical or only one is provided:
  /// - Returns `"Réservé par [name]"`
  static String formatDelegationLabel({
    String? creator,
    String? bookedFor,
    bool isForMe = false,
    bool isByMe = false,
  }) {
    final c = creator?.trim();
    final b = bookedFor?.trim();

    final bool effectivelyForMe = isForMe || (b != null && b.toLowerCase() == 'vous');
    final bool effectivelyByMe = isByMe || (c != null && c.toLowerCase() == 'vous');

    // Case 1: Both creator and bookedFor are present and differ
    if (c != null && b != null && c.isNotEmpty && b.isNotEmpty && c.toLowerCase() != b.toLowerCase()) {
      if (effectivelyForMe) {
        return 'Réservé par $c pour vous';
      }
      if (effectivelyByMe) {
        return 'Réservé pour $b par vous';
      }
      return 'Réservé pour $b par $c';
    }

    // Case 2: Only bookedFor is present or creator == bookedFor
    if (b != null && b.isNotEmpty) {
      if (effectivelyForMe) {
        return 'Réservé pour vous';
      }
      return 'Réservé par $b';
    }

    // Case 3: Only creator is present
    if (c != null && c.isNotEmpty) {
      if (effectivelyByMe) {
        return 'Réservé par vous';
      }
      return 'Réservé par $c';
    }

    return 'Réservé par un collègue';
  }

  /// Parses an API [bookedTimeSlot] JSON structure to determine the display label for an occupant.
  ///
  /// Supports various MyRoomz key names (`creator`, `bookedBy`, `bookedFor`, `user`, `organizer`, `owner`).
  /// If delegated (`creator != bookedFor`), returns `"Réservé pour [X] par [Y]"`
  /// (or `"Réservé par [Y] pour vous"` if [myUserId] matches bookedFor).
  /// If not delegated, returns the occupant's name.
  static String extractReservationOccupant(
    Map<String, dynamic> bookedTimeSlot, {
    String? myUserId,
  }) {
    final creator = bookedTimeSlot['creator'] ?? bookedTimeSlot['bookedBy'];
    final organizer = bookedTimeSlot['organizer'];
    final bookedFor = bookedTimeSlot['bookedFor'] ?? bookedTimeSlot['user'] ?? bookedTimeSlot['owner'];

    String? cName = _extractName(creator);
    String? cId = _extractId(creator);

    String? bName = _extractName(bookedFor) ?? _extractName(organizer);
    String? bId = _extractId(bookedFor) ?? _extractId(organizer);

    // If bookedFor is null, also check 'user' or 'owner'
    if (bName == null) {
      final target = bookedTimeSlot['user'] ?? bookedTimeSlot['owner'];
      bName = _extractName(target);
      bId = _extractId(target);
    }

    final bool isDifferent = (cId != null && bId != null && cId.toLowerCase() != bId.toLowerCase()) ||
        (cName != null && bName != null && cName.trim().toLowerCase() != bName.trim().toLowerCase()) ||
        (bookedTimeSlot['bookedFor'] != null);

    final bool isDelegated = creator != null && (bookedFor != null || organizer != null) && isDifferent;

    if (isDelegated && cName != null && bName != null && cName.trim().toLowerCase() != bName.trim().toLowerCase()) {
      final isForMe = myUserId != null && bId != null && bId.toLowerCase() == myUserId.toLowerCase();
      final isByMe = myUserId != null && cId != null && cId.toLowerCase() == myUserId.toLowerCase();
      return formatDelegationLabel(
        creator: cName,
        bookedFor: bName,
        isForMe: isForMe,
        isByMe: isByMe,
      );
    }

    return bName ?? cName ?? "Quelqu'un d'autre";
  }

  /// Formats the subtitle shown in the Calendar Date Tap Details Bottom Sheet.
  /// e.g. "Réservé pour Bob par Alice." or "Réservé par Bob."
  static String formatOccupiedSubtitle(String rawOccupant) {
    final trimmed = rawOccupant.trim();
    if (trimmed.startsWith('Réservé ') || trimmed.startsWith('réservé ')) {
      return trimmed.endsWith('.') ? trimmed : '$trimmed.';
    }
    if (trimmed.contains('|')) {
      final parts = trimmed.split('|');
      final b = parts[0];
      final c = parts.length > 1 ? parts[1] : null;
      final label = formatDelegationLabel(creator: c, bookedFor: b);
      return '$label.';
    }
    return 'Réservé par $trimmed.';
  }

  /// Formats the subtitle shown in the Home Screen Upcoming Bookings card.
  /// e.g. "Indisponible (réservé pour Bob par Alice)" or "Indisponible (réservé par Bob)"
  static String formatOccupiedHomeSubtitle(dynamic rawName) {
    final str = rawName?.toString().trim() ?? "qqn d'autre";
    if (str.startsWith('Réservé ') || str.startsWith('réservé ')) {
      final lower = str[0].toLowerCase() + str.substring(1);
      return 'Indisponible ($lower)';
    }
    if (str.contains('|')) {
      final parts = str.split('|');
      final b = parts[0];
      final c = parts.length > 1 ? parts[1] : null;
      final label = formatDelegationLabel(creator: c, bookedFor: b);
      final lower = label[0].toLowerCase() + label.substring(1);
      return 'Indisponible ($lower)';
    }
    return 'Indisponible (réservé par $str)';
  }

  /// Formats the subtitle for delegated bookings in Home Screen cards.
  static String formatDelegatedHomeSubtitle({
    required String delegateName,
    String? location,
    String? creatorName,
    bool isForMe = false,
  }) {
    final c = creatorName?.trim();
    final d = delegateName.trim();
    final loc = (location != null && location.trim().isNotEmpty) ? ' ($location)' : '';

    if (c != null && c.isNotEmpty && c.toLowerCase() != d.toLowerCase()) {
      final label = formatDelegationLabel(creator: c, bookedFor: d, isForMe: isForMe);
      return '$label$loc';
    }

    return 'Réservé pour $d$loc';
  }

  /// Formats the tooltip or accessible description for a calendar day cell.
  static String formatOccupiedCalendarTooltip(String rawOccupant) {
    final trimmed = rawOccupant.trim();
    if (trimmed.startsWith('Réservé ') || trimmed.startsWith('réservé ')) {
      return trimmed;
    }
    if (trimmed.contains('|')) {
      final parts = trimmed.split('|');
      final b = parts[0];
      final c = parts.length > 1 ? parts[1] : null;
      return formatDelegationLabel(creator: c, bookedFor: b);
    }
    return 'Réservé par $trimmed';
  }

  static String? _extractName(dynamic entity) {
    if (entity == null) return null;
    if (entity is Map) {
      return entity['name']?.toString() ??
          entity['displayName']?.toString() ??
          entity['fullName']?.toString();
    }
    if (entity is String && entity.trim().isNotEmpty) {
      return entity.trim();
    }
    return null;
  }

  static String? _extractId(dynamic entity) {
    if (entity == null) return null;
    if (entity is Map) {
      return entity['id']?.toString() ??
          entity['userId']?.toString() ??
          entity['email']?.toString() ??
          entity['mail']?.toString();
    }
    if (entity is String && entity.trim().isNotEmpty) {
      return entity.trim();
    }
    return null;
  }
}
