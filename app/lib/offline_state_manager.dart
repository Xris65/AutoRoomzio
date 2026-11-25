import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Central singleton managing network connectivity state for AutoRoomzio.
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

  static const Set<String> _connectivityRuntimeTypes = <String>{
    'SocketException',
    '_ClientSocketException',
    'HandshakeException',
    'TlsException',
    'CertificateException',
    'HttpException',
    '_HttpException',
    'WebSocketException',
  };

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
    final runtimeTypeName = error.runtimeType.toString();
    if (error is http.ClientException ||
        error is TimeoutException ||
        _connectivityRuntimeTypes.contains(runtimeTypeName)) {
      return true;
    }
    final str = error.toString().toLowerCase();
    return str.contains('socketexception') ||
        str.contains('clientexception') ||
        str.contains('timeoutexception') ||
        str.contains('httpexception') ||
        str.contains('xmlhttprequest') ||
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
  static bool checkConnectivityError(Object error) =>
      instance.isConnectivityError(error);
}

/// An [http.BaseClient] decorator that wraps an inner client and intercepts
/// responses, body streams, and errors to update [OfflineStateManager].
class OfflineAwareHttpClient extends http.BaseClient {
  final http.Client _inner;
  final OfflineStateManager _stateManager;
  final Duration _timeout;

  OfflineAwareHttpClient([
    http.Client? inner,
    OfflineStateManager? stateManager,
    Duration timeout = const Duration(seconds: 20),
  ])  : _inner = inner is OfflineAwareHttpClient
            ? inner._inner
            : (inner ?? http.Client()),
        _stateManager = stateManager ?? OfflineStateManager.instance,
        _timeout = timeout;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    try {
      final response = await _inner.send(request).timeout(_timeout);
      // Any response from the server (2xx, 4xx, 5xx) proves network connectivity.
      _stateManager.markOnline();

      final Stream<List<int>> guardedStream = _guardBodyStream(response.stream);

      return http.StreamedResponse(
        guardedStream,
        response.statusCode,
        contentLength: response.contentLength,
        request: response.request,
        headers: response.headers,
        isRedirect: response.isRedirect,
        persistentConnection: response.persistentConnection,
        reasonPhrase: response.reasonPhrase,
      );
    } on TimeoutException {
      _stateManager.markOffline();
      rethrow;
    } catch (e) {
      if (_stateManager.isConnectivityError(e)) {
        _stateManager.markOffline();
      }
      rethrow;
    }
  }

  /// Wraps a response body stream with an idle timeout (reset on every chunk)
  /// and connectivity error reporting. Errors are always forwarded to the
  /// consumer (never swallowed). Implemented with an explicit [Timer] instead
  /// of [Stream.timeout] so it also behaves deterministically under FakeAsync.
  Stream<List<int>> _guardBodyStream(Stream<List<int>> source) {
    late final StreamController<List<int>> controller;
    StreamSubscription<List<int>>? subscription;
    Timer? idleTimer;

    void cancelTimer() {
      idleTimer?.cancel();
      idleTimer = null;
    }

    void armTimer() {
      cancelTimer();
      idleTimer = Timer(_timeout, () {
        _stateManager.markOffline();
        if (!controller.isClosed) {
          controller.addError(
            TimeoutException('Response stream timed out', _timeout),
          );
          unawaited(controller.close());
        }
        unawaited(subscription?.cancel());
        subscription = null;
      });
    }

    controller = StreamController<List<int>>(
      sync: true,
      onListen: () {
        armTimer();
        subscription = source.listen(
          (List<int> chunk) {
            armTimer();
            controller.add(chunk);
          },
          onError: (Object error, StackTrace stackTrace) {
            cancelTimer();
            if (_stateManager.isConnectivityError(error)) {
              _stateManager.markOffline();
            }
            controller.addError(error, stackTrace);
          },
          onDone: () {
            cancelTimer();
            subscription = null;
            unawaited(controller.close());
          },
        );
      },
      onCancel: () {
        cancelTimer();
        final pending = subscription?.cancel();
        subscription = null;
        return pending;
      },
    );
    return controller.stream;
  }

  @override
  void close() {
    _inner.close();
    super.close();
  }
}
