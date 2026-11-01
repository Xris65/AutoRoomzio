import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:auto_roomzio/utils/error_sanitizer.dart';

void main() {
  group('ErrorSanitizer - Bug #4 Sanitizer Tests', () {
    test('SocketException returns friendly connectivity message', () {
      const error = SocketException('Failed host lookup: api.my.roomz.io');
      final result = sanitizeErrorMessage(error);
      expect(result, "Impossible de joindre le serveur. Veuillez vérifier votre connexion.");
      expect(result.contains('http'), isFalse);
      expect(result.contains('roomz'), isFalse);
    });

    test('http.ClientException with HTTPS URL returns friendly connectivity message without URL', () {
      final error = http.ClientException(
        'Connection closed before full header was received, uri=https://api.my.roomz.io/api/bookings',
      );
      final result = sanitizeErrorMessage(error);
      expect(result, "Impossible de joindre le serveur. Veuillez vérifier votre connexion.");
      expect(result.contains('https://'), isFalse);
      expect(result.contains('api.my.roomz.io'), isFalse);
    });

    test('TimeoutException returns friendly connectivity message', () {
      final error = TimeoutException('The connection has timed out after 10 seconds');
      final result = sanitizeErrorMessage(error);
      expect(result, "Impossible de joindre le serveur. Veuillez vérifier votre connexion.");
    });

    test('XMLHttpRequest error string (Web) returns friendly connectivity message', () {
      const error = 'ClientException: XMLHttpRequest error., uri=https://api.my.roomz.io/api/workspaces';
      final result = sanitizeErrorMessage(error);
      expect(result, "Impossible de joindre le serveur. Veuillez vérifier votre connexion.");
      expect(result.contains('https://'), isFalse);
    });

    test('HTTP 401 Unauthorized returns session expired message', () {
      const error = 'ClientException: 401 Unauthorized at https://api.my.roomz.io/api/users';
      final result = sanitizeErrorMessage(error);
      expect(result, "Session expirée. Veuillez vous reconnecter.");
      expect(result.contains('https://'), isFalse);
    });

    test('HTTP 403 Forbidden returns session expired message', () {
      const error = 'HttpException: 403 Forbidden';
      final result = sanitizeErrorMessage(error);
      expect(result, "Session expirée. Veuillez vous reconnecter.");
    });

    test('String containing explicit session expiree returns session expired message', () {
      const error = 'Session expirée. Veuillez vous reconnecter.';
      final result = sanitizeErrorMessage(error);
      expect(result, "Session expirée. Veuillez vous reconnecter.");
    });

    test('HTTPS URL in error message is NEVER exposed', () {
      const rawError = 'Error communicating with https://api.my.roomz.io/v1/spaces/123/reserve';
      final result = sanitizeErrorMessage(rawError, fallback: "Erreur lors de la réservation.");
      expect(result.contains('https://'), isFalse);
      expect(result.contains('api.my.roomz.io'), isFalse);
      expect(result, "Erreur lors de la réservation.");
    });

    test('Raw stacktrace is NEVER exposed', () {
      const rawError = '#0 ApiService.reserve (package:autoroomzio/api_service.dart:273)\n#1 TeamMapScreen._bookDesk';
      final result = sanitizeErrorMessage(rawError);
      expect(result.contains('#0'), isFalse);
      expect(result.contains('package:'), isFalse);
      expect(result, "Une erreur est survenue. Veuillez réessayer.");
    });

    test('Raw technical JSON payload is NEVER exposed', () {
      const rawError = '{"error": "internal_server_error", "code": 500, "message": "Failed db query"}';
      final result = sanitizeErrorMessage(rawError);
      expect(result.contains('{"error"'), isFalse);
      expect(result.contains('internal_server_error'), isFalse);
      expect(result, "Une erreur est survenue. Veuillez réessayer.");
    });

    test('Clean user-friendly French message is preserved', () {
      const cleanMessage = 'Ce bureau n\'est plus disponible à cette date';
      final result = sanitizeErrorMessage(cleanMessage);
      expect(result, cleanMessage);
    });
  });
}
