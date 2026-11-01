import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Central singleton managing network connectivity state for AutoRoomzio (v1.6.2).
/// Follows Requirements R1 & R2:
/// - Starts by default in online mode (`isOffline == false`).
/// - Unconditionally allows all outgoing requests to proceed without blocking,
///   throttling, or short-circuiting (R1).
/// - Switches `isOffline = true` when an API request fails due to a network connectivity error (R2).
/// - Switches `isOffline = false` immediately when any API request receives an HTTP response (R2).
class OfflineStateManager {
  OfflineStateManager._();
  static final OfflineStateManager instance = OfflineStateManager._();

  /// Factory constructor returning the singleton instance.
  factory OfflineStateManager() => instance;

  /// Reactive notifier for widget tree subscription.
  final ValueNotifier<bool> isOfflineNotifier = ValueNotifier<bool>(false);

  /// Synchronous getter indicating whether the application is offline.
  bool get isOffline => isOfflineNotifier.value;

  /// Sets offline status to true.
  void markOffline() {
    if (isOfflineNotifier.value != true) {
      isOfflineNotifier.value = true;
    }
  }

  /// Sets offline status to false.
  void markOnline() {
    if (isOfflineNotifier.value != false) {
      isOfflineNotifier.value = false;
    }
  }

  /// Resets offline status to false (useful for test isolation).
  void reset() {
    isOfflineNotifier.value = false;
  }

  /// Evaluates an exception and switches to offline if it is a connectivity failure.
  void reportException(Object error) {
    if (isConnectivityError(error)) {
      markOffline();
    }
  }

  /// Evaluates whether an error/exception represents a network connectivity failure.
  bool isConnectivityError(Object error) {
    if (error is SocketException ||
        error is http.ClientException ||
        error is TimeoutException) {
      return true;
    }
    final str = error.toString().toLowerCase();
    return str.contains('socketexception') ||
           str.contains('clientexception') ||
           str.contains('timeoutexception') ||
           str.contains('httpexception') ||
           str.contains('network is unreachable') ||
           str.contains('network unreachable') ||
           str.contains('connection refused') ||
           str.contains('connection reset') ||
           str.contains('failed host lookup') ||
           str.contains('network error') ||
           str.contains('software caused connection abort') ||
           str.contains('connection closed before full header was received') ||
           str.contains('connection closed') ||
           str.contains('handshakeexception') ||
           str.contains('tlsexception') ||
           str.contains('connection timed out') ||
           str.contains('broken pipe');
  }

  /// Static helper for connectivity error detection.
  static bool checkConnectivityError(Object error) => instance.isConnectivityError(error);
}

/// An [http.BaseClient] decorator that wraps an inner client and intercepts
/// responses and errors to update [OfflineStateManager].
///
/// Follows Requirements R1 & R2:
/// - Never blocks, throttles, or short-circuits outgoing requests.
/// - Always forwards requests directly to the wrapped client.
/// - On receiving any HTTP response (2xx, 4xx, 5xx), calls `markOnline()`.
/// - On catching a connectivity error, calls `markOffline()`, and rethrows.
class OfflineAwareHttpClient extends http.BaseClient {
  final http.Client? _inner;
  final OfflineStateManager _stateManager;

  OfflineAwareHttpClient([
    http.Client? inner,
    OfflineStateManager? stateManager,
  ])  : _inner = (inner is OfflineAwareHttpClient ? inner._inner : inner),
        _stateManager = stateManager ?? OfflineStateManager.instance;

  http.Client get _effectiveInner => _inner ?? http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final client = _effectiveInner;
    try {
      final response = await client.send(request);
      // Any response from the server (2xx, 4xx, 5xx) proves network connectivity.
      _stateManager.markOnline();
      return response;
    } catch (e) {
      if (_stateManager.isConnectivityError(e)) {
        _stateManager.markOffline();
      }
      rethrow;
    }
  }

  @override
  void close() {
    _inner?.close();
    super.close();
  }
}
