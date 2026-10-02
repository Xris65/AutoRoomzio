import 'package:flutter/foundation.dart';

/// Status codes representing the outcome of a desk reservation attempt.
enum BookingStatus {
  success,
  conflictDesk,
  conflictColleague,
  invalidDate,
  unauthorized,
  forbidden,
  serverError,
  networkError,
}

/// Typed outcome of a desk reservation for self or a delegated colleague.
@immutable
class BookingResult {
  final BookingStatus status;
  final String message;
  final String? eventId;
  final String? colleagueId;
  final String? colleagueName;
  final String? colleagueEmail;

  const BookingResult({
    required this.status,
    required this.message,
    this.eventId,
    this.colleagueId,
    this.colleagueName,
    this.colleagueEmail,
  });

  /// Factory constructor for successful reservations.
  const BookingResult.success({
    this.eventId,
    this.colleagueId,
    this.colleagueName,
    this.colleagueEmail,
    String? message,
  })  : status = BookingStatus.success,
        message = message ??
            (colleagueName != null
                ? 'Bureau réservé pour $colleagueName !'
                : 'Bureau réservé avec succès !');

  /// Factory constructor for desk conflict (desk taken by someone else).
  const BookingResult.conflictDesk({
    String? message,
    this.colleagueId,
    this.colleagueName,
    this.colleagueEmail,
  })  : status = BookingStatus.conflictDesk,
        message = message ?? 'Ce bureau est déjà réservé par quelqu\'un d\'autre.',
        eventId = null;

  /// Factory constructor for colleague conflict (colleague already has a booking).
  const BookingResult.conflictColleague({
    String? message,
    this.colleagueId,
    this.colleagueName,
    this.colleagueEmail,
  })  : status = BookingStatus.conflictColleague,
        message = message ??
            (colleagueName != null
                ? '$colleagueName a déjà une réservation ce jour-là.'
                : 'Ce collègue a déjà une réservation ce jour-là.'),
        eventId = null;

  /// Convenience boolean flags.
  bool get isSuccess => status == BookingStatus.success;
  bool get isConflict =>
      status == BookingStatus.conflictDesk ||
      status == BookingStatus.conflictColleague;
  bool get isConflictDesk => status == BookingStatus.conflictDesk;
  bool get isConflictColleague => status == BookingStatus.conflictColleague;

  /// Returns clear, user-facing French feedback based on the reservation status.
  String getLocalizedMessage([String? colleagueName]) {
    final name = colleagueName ?? this.colleagueName;
    switch (status) {
      case BookingStatus.success:
        return name != null ? 'Bureau réservé pour $name !' : 'Bureau réservé avec succès !';
      case BookingStatus.conflictColleague:
        if (message.isNotEmpty &&
            !message.contains('a déjà une réservation') &&
            message != 'Ce collègue a déjà une réservation ce jour-là.') {
          return message;
        }
        return name != null
            ? '$name a déjà une réservation ce jour-là.'
            : 'Ce collègue a déjà une réservation ce jour-là.';
      case BookingStatus.conflictDesk:
        return 'Ce bureau est déjà réservé par quelqu\'un d\'autre.';
      case BookingStatus.invalidDate:
        if (message.isNotEmpty && message != 'Invalid date' && !message.contains('13 jours')) {
          return message;
        }
        return "La réservation manuelle est limitée à 13 jours à l'avance.";
      case BookingStatus.unauthorized:
        return 'Session expirée. Reconnexion requise.';
      case BookingStatus.forbidden:
        return 'Votre profil n\'a pas les droits pour réserver pour un tiers.';
      case BookingStatus.serverError:
      case BookingStatus.networkError:
        return message.isNotEmpty ? message : 'Erreur de connexion aux serveurs MyRoomz.';
    }
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is BookingResult &&
          runtimeType == other.runtimeType &&
          status == other.status &&
          message == other.message &&
          eventId == other.eventId &&
          colleagueId == other.colleagueId &&
          colleagueName == other.colleagueName &&
          colleagueEmail == other.colleagueEmail;

  @override
  int get hashCode => Object.hash(status, message, eventId, colleagueId, colleagueName, colleagueEmail);

  @override
  String toString() =>
      'BookingResult(status: $status, eventId: $eventId, colleague: $colleagueName, email: $colleagueEmail, message: $message)';
}
