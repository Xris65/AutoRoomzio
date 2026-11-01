import 'dart:async';
import 'dart:io';
import 'package:http/http.dart' as http;

/// Utility class for sanitizing and formatting error messages shown to the user.
///
/// Prevents exposing technical details, raw exception strings, stack traces,
/// internal JSON payloads, and sensitive server URLs (especially HTTPS endpoints).
class ErrorSanitizer {
  static const String connectionErrorMessage =
      "Impossible de joindre le serveur. Veuillez vérifier votre connexion.";

  static const String sessionExpiredMessage =
      "Session expirée. Veuillez vous reconnecter.";

  static const String defaultErrorMessage =
      "Une erreur est survenue. Veuillez réessayer.";

  /// Returns a clean, user-friendly error message.
  ///
  /// - If the error indicates a network or connectivity issue (SocketException,
  ///   ClientException, TimeoutException, XMLHttpRequest, etc.), returns
  ///   [connectionErrorMessage].
  /// - If the error indicates an authentication/authorization failure (401, 403,
  ///   unauthorized, session expirée), returns [sessionExpiredMessage].
  /// - NEVER exposes HTTPS URLs, raw stack traces, JSON, or exception names to the UI.
  /// - If the message contains technical tokens or URLs, replaces it with [fallback]
  ///   or [defaultErrorMessage].
  static String sanitize(dynamic error, {String? fallback}) {
    if (error == null) {
      return fallback ?? defaultErrorMessage;
    }

    // 1. Direct type inspection for network/connection exceptions
    if (error is SocketException ||
        error is http.ClientException ||
        error is TimeoutException) {
      return connectionErrorMessage;
    }

    final rawStr = error.toString().trim();
    if (rawStr.isEmpty) {
      return fallback ?? defaultErrorMessage;
    }

    final lower = rawStr.toLowerCase();

    // 2. Auth / Session expiration checks (401, 403, unauthorized, forbidden, etc.)
    final hasAuthError = RegExp(r'\b(401|403)\b').hasMatch(lower) ||
        lower.contains('unauthorized') ||
        lower.contains('forbidden') ||
        lower.contains('session expirée') ||
        lower.contains('session expiree') ||
        lower.contains('token expired') ||
        lower.contains('jwt expired') ||
        lower.contains('invalid token');
    if (hasAuthError) {
      return sessionExpiredMessage;
    }

    // 3. String-based connectivity patterns
    final isConnectionError = lower.contains('socketexception') ||
        lower.contains('clientexception') ||
        lower.contains('timeoutexception') ||
        lower.contains('httpexception') ||
        lower.contains('xmlhttprequest') ||
        lower.contains('failed host lookup') ||
        lower.contains('network is unreachable') ||
        lower.contains('network unreachable') ||
        lower.contains('connection refused') ||
        lower.contains('connection reset') ||
        lower.contains('connection timed out') ||
        lower.contains('timed out') ||
        lower.contains('handshakeexception') ||
        lower.contains('tlsexception') ||
        lower.contains('network error') ||
        lower.contains('connection closed') ||
        lower.contains('software caused connection abort') ||
        lower.contains('broken pipe') ||
        lower.contains('no internet') ||
        lower.contains('econnrefused') ||
        lower.contains('enotfound') ||
        lower.contains('failed to connect') ||
        lower.contains('network failure');
    if (isConnectionError) {
      return connectionErrorMessage;
    }

    // 4. Check for technical leakage: URLs (http/https), stack traces, JSON, raw exceptions
    final hasUrl = RegExp(r'https?://[^\s<>"]+').hasMatch(rawStr);
    final hasStackTrace = RegExp(r'(#\d+\s+|dart:[a-zA-Z0-9_]+|\.dart:\d+)').hasMatch(rawStr);
    final hasRawJson = RegExp(r'\{.*"(?:error|message|status|code)".*\}', dotAll: true).hasMatch(rawStr);
    final hasTechnicalException = RegExp(
      r'(Exception:|Error:|FormatException|NoSuchMethodError|TypeError|RangeError)',
      caseSensitive: false,
    ).hasMatch(rawStr);

    if (hasUrl || hasStackTrace || hasRawJson || hasTechnicalException) {
      if (fallback != null && fallback.trim().isNotEmpty) {
        return sanitize(fallback);
      }
      return defaultErrorMessage;
    }

    return rawStr;
  }
}

/// Convenience top-level function for [ErrorSanitizer.sanitize].
String sanitizeErrorMessage(dynamic error, {String? fallback}) =>
    ErrorSanitizer.sanitize(error, fallback: fallback);
